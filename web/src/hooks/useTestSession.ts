import { useCallback, useEffect, useRef, useState, type Dispatch, type SetStateAction } from 'react'

import { applyRoomEvent, emptyBoard, parsePossibleActions } from '../board/applyEvent'
import { wsUrl } from '../net/wsUrl'
import type { BoardSnapshot, LogEntry, PendingRequest, Phase, WireAction } from '../types'

const CAPACITY = 4

/** bot id 最高位为 1；JSON 解析后仍远大于 MAX_SAFE_INTEGER */
function isBotPlayerId (id: unknown): boolean {
  return typeof id === 'number' && Number.isFinite(id) && id > Number.MAX_SAFE_INTEGER
}

function memberKey (id: unknown): string | null {
  if (typeof id === 'number' && Number.isFinite(id)) return String(id)
  if (typeof id === 'string' && id.length > 0) return id
  return null
}

let logSeq = 0

function pushLog (
  setLogs: Dispatch<SetStateAction<LogEntry[]>>,
  dir: LogEntry['dir'],
  channel: LogEntry['channel'],
  text: string,
) {
  setLogs((prev) => {
    const next = [...prev, { id: ++logSeq, at: Date.now(), dir, channel, text }]
    return next.length > 80 ? next.slice(-80) : next
  })
}

export function useTestSession () {
  const [phase, setPhase] = useState<Phase>('idle')
  const [playerId, setPlayerId] = useState<number | null>(null)
  const [roomId, setRoomId] = useState<number | null>(null)
  const [isHost, setIsHost] = useState(false)
  const [members, setMembers] = useState<string[]>([])
  const [lobbyConnected, setLobbyConnected] = useState(false)
  const [roomConnected, setRoomConnected] = useState(false)
  const [board, setBoard] = useState<BoardSnapshot>(emptyBoard)
  const [pending, setPending] = useState<PendingRequest | null>(null)
  const [logs, setLogs] = useState<LogEntry[]>([])
  const [busy, setBusy] = useState(false)
  const [status, setStatus] = useState('未连接')

  const lobbyRef = useRef<WebSocket | null>(null)
  const roomRef = useRef<WebSocket | null>(null)
  const reqIdRef = useRef(1)
  const playerIdRef = useRef<number | null>(null)
  const roomIdRef = useRef<number | null>(null)
  const meSeatRef = useRef(0)

  useEffect(() => { playerIdRef.current = playerId }, [playerId])
  useEffect(() => { roomIdRef.current = roomId }, [roomId])
  useEffect(() => { meSeatRef.current = board.meSeat }, [board.meSeat])

  const nextReq = () => {
    const id = reqIdRef.current
    reqIdRef.current += 1
    return id
  }

  const resetTable = useCallback(() => {
    setRoomId(null)
    setIsHost(false)
    setMembers([])
  }, [])

  const addMember = useCallback((id: unknown) => {
    const key = memberKey(id)
    if (key == null) return
    setMembers((prev) => (prev.includes(key) ? prev : [...prev, key]))
  }, [])

  const removeMember = useCallback((id: unknown) => {
    const key = memberKey(id)
    if (key == null) return
    setMembers((prev) => prev.filter((m) => m !== key))
  }, [])

  const sendLobby = useCallback((obj: Record<string, unknown>) => {
    const ws = lobbyRef.current
    if (!ws || ws.readyState !== WebSocket.OPEN) return
    const text = JSON.stringify(obj)
    ws.send(text)
    pushLog(setLogs, 'out', 'lobby', text)
  }, [])

  const sendRoom = useCallback((obj: Record<string, unknown>) => {
    const ws = roomRef.current
    if (!ws || ws.readyState !== WebSocket.OPEN) return
    const text = JSON.stringify(obj)
    ws.send(text)
    pushLog(setLogs, 'out', 'room', text)
  }, [])

  const closeLobby = useCallback(() => {
    lobbyRef.current?.close()
    lobbyRef.current = null
    setLobbyConnected(false)
  }, [])

  const closeRoom = useCallback(() => {
    roomRef.current?.close()
    roomRef.current = null
    setRoomConnected(false)
  }, [])

  const connectRoom = useCallback((rid: number, pid: number) => {
    closeRoom()
    const url = wsUrl(`/ws/room/${rid}?player_id=${pid}`)
    pushLog(setLogs, 'sys', 'ui', `连接 room ${url}`)
    const ws = new WebSocket(url)
    roomRef.current = ws
    ws.onopen = () => {
      setRoomConnected(true)
      setPhase('room')
      setStatus(`对局中 · room ${rid}`)
    }
    ws.onclose = () => {
      setRoomConnected(false)
      if (roomRef.current === ws) {
        setStatus('room 已断开')
      }
    }
    ws.onerror = () => {
      pushLog(setLogs, 'sys', 'room', 'room WebSocket error')
    }
    ws.onmessage = (ev) => {
      const text = String(ev.data)
      pushLog(setLogs, 'in', 'room', text)
      let msg: Record<string, unknown>
      try {
        msg = JSON.parse(text) as Record<string, unknown>
      } catch {
        return
      }
      const type = msg.type
      if (type === 'request_action') {
        setPending({
          requestId: msg.request_id as number,
          actions: parsePossibleActions(msg.possible_actions),
          deadlineMs: (msg.time as { deadline_ms?: number } | undefined)?.deadline_ms,
        })
      } else if (type === 'action_ack') {
        const ridAck = msg.request_id as number
        setPending((p) => (p && p.requestId === ridAck ? null : p))
      } else if (type === 'end_game') {
        setPhase('ended')
        setStatus('终局')
        setPending(null)
      }
      setBoard((b) => applyRoomEvent(b, msg))
    }
  }, [closeRoom])

  const handleLobbyMessage = useCallback((text: string) => {
    pushLog(setLogs, 'in', 'lobby', text)
    let msg: Record<string, unknown>
    try {
      msg = JSON.parse(text) as Record<string, unknown>
    } catch {
      return
    }
    switch (msg.type) {
      case 'welcome':
        setPlayerId(msg.player_id as number)
        setStatus(`lobby · player ${msg.player_id as number}`)
        break
      case 'pong':
        break
      case 'room_created':
        setRoomId(msg.room_id as number)
        setIsHost(msg.is_host === true)
        setMembers([])
        setStatus(`已创建 room ${msg.room_id as number}`)
        break
      case 'room_joined': {
        const rid = msg.room_id as number
        setRoomId(rid)
        setIsHost(msg.is_host === true)
        const selfId = playerIdRef.current
        if (selfId != null) addMember(selfId)
        setStatus(`${msg.is_host === true ? '房主' : '成员'} · room ${rid}`)
        break
      }
      case 'member_joined':
        if (typeof msg.is_host === 'boolean') setIsHost(msg.is_host)
        addMember(msg.player_id)
        break
      case 'member_left':
        if (typeof msg.is_host === 'boolean') setIsHost(msg.is_host)
        removeMember(msg.player_id)
        break
      case 'bot_added':
      case 'bot_removed':
        // 席位以 member_joined / member_left 为准，避免与推送重复计数
        break
      case 'game_started': {
        const rid = (msg.room_id as number | undefined) ?? roomIdRef.current
        const pid = playerIdRef.current
        if (rid == null || pid == null) break
        setRoomId(rid)
        setStatus('开局，切换 room…')
        closeLobby()
        connectRoom(rid, pid)
        break
      }
      case 'err':
        setStatus(`错误 ${(msg.code as string) ?? ''} ${String(msg.msg ?? '')}`)
        setBusy(false)
        break
      default:
        break
    }
  }, [addMember, closeLobby, connectRoom, removeMember])

  const connectLobby = useCallback(() => {
    closeLobby()
    closeRoom()
    setBoard(emptyBoard())
    setPending(null)
    resetTable()
    setPhase('lobby')
    const url = wsUrl('/ws/lobby')
    pushLog(setLogs, 'sys', 'ui', `连接 lobby ${url}`)
    const ws = new WebSocket(url)
    lobbyRef.current = ws
    ws.onopen = () => {
      setLobbyConnected(true)
      setStatus('lobby 已连接')
    }
    ws.onclose = () => {
      setLobbyConnected(false)
      if (lobbyRef.current === ws && phase !== 'room' && phase !== 'ended') {
        setStatus('lobby 已断开')
      }
    }
    ws.onerror = () => pushLog(setLogs, 'sys', 'lobby', 'lobby WebSocket error')
    ws.onmessage = (ev) => handleLobbyMessage(String(ev.data))
  }, [closeLobby, closeRoom, handleLobbyMessage, phase, resetTable])

  useEffect(() => {
    if (!lobbyConnected) return
    const t = window.setInterval(() => {
      sendLobby({ type: 'ping' })
    }, 15000)
    return () => window.clearInterval(t)
  }, [lobbyConnected, sendLobby])

  useEffect(() => () => {
    lobbyRef.current?.close()
    roomRef.current?.close()
  }, [])

  const createRoom = useCallback(() => {
    sendLobby({ type: 'create_room', request_id: nextReq() })
  }, [sendLobby])

  const joinRoom = useCallback((rid: number) => {
    if (!Number.isFinite(rid) || rid <= 0) {
      setStatus('请输入有效 room_id')
      return
    }
    sendLobby({ type: 'join_room', request_id: nextReq(), room_id: rid })
  }, [sendLobby])

  const addBot = useCallback(() => {
    const rid = roomIdRef.current
    if (rid == null) return
    sendLobby({ type: 'add_bot', request_id: nextReq(), room_id: rid })
  }, [sendLobby])

  const startGame = useCallback(() => {
    const rid = roomIdRef.current
    if (rid == null) return
    sendLobby({ type: 'start_game', request_id: nextReq(), room_id: rid })
  }, [sendLobby])

  /** create → 加满 bot → start（串行等回包） */
  const quickStart = useCallback(async () => {
    if (!lobbyRef.current || lobbyRef.current.readyState !== WebSocket.OPEN) {
      setStatus('请先连接 lobby')
      return
    }
    setBusy(true)
    setStatus('一键开桌中…')

    const waitType = (types: string[], timeoutMs = 5000) =>
      new Promise<Record<string, unknown>>((resolve, reject) => {
        const ws = lobbyRef.current
        if (!ws) {
          reject(new Error('no lobby'))
          return
        }
        const timer = window.setTimeout(() => {
          ws.removeEventListener('message', onMsg)
          reject(new Error('timeout'))
        }, timeoutMs)
        const onMsg = (ev: MessageEvent) => {
          try {
            const msg = JSON.parse(String(ev.data)) as Record<string, unknown>
            if (types.includes(msg.type as string)) {
              window.clearTimeout(timer)
              ws.removeEventListener('message', onMsg)
              resolve(msg)
            }
            if (msg.type === 'err') {
              window.clearTimeout(timer)
              ws.removeEventListener('message', onMsg)
              reject(new Error(String(msg.msg ?? msg.code)))
            }
          } catch { /* ignore */ }
        }
        ws.addEventListener('message', onMsg)
      })

    try {
      sendLobby({ type: 'create_room', request_id: nextReq() })
      const created = await waitType(['room_created'])
      const rid = created.room_id as number
      setRoomId(rid)
      roomIdRef.current = rid
      setIsHost(created.is_host === true)

      for (let i = 0; i < CAPACITY - 1; i++) {
        sendLobby({ type: 'add_bot', request_id: nextReq(), room_id: rid })
        await waitType(['bot_added'])
      }

      sendLobby({ type: 'start_game', request_id: nextReq(), room_id: rid })
      // game_started 由 handleLobbyMessage 切 room
      await waitType(['game_started'])
    } catch (e) {
      setStatus(`一键开桌失败: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setBusy(false)
    }
  }, [sendLobby])

  const submitAction = useCallback((action: WireAction) => {
    if (!pending) return
    const payload: Record<string, unknown> = {
      ...action,
      request_id: pending.requestId,
      actor: meSeatRef.current,
    }
    sendRoom(payload)
  }, [pending, sendRoom])

  const bots = members.filter((m) => isBotPlayerId(Number(m))).length
  const occupied = roomId != null ? members.length : 0

  return {
    phase,
    playerId,
    roomId,
    isHost,
    bots,
    occupied,
    lobbyConnected,
    roomConnected,
    board,
    pending,
    logs,
    busy,
    status,
    connectLobby,
    createRoom,
    joinRoom,
    addBot,
    startGame,
    quickStart,
    submitAction,
    closeAll: () => {
      closeLobby()
      closeRoom()
      resetTable()
      setPhase('idle')
      setStatus('已断开')
    },
  }
}
