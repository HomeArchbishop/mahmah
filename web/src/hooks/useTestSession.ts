import { useCallback, useEffect, useRef, useState, type Dispatch, type SetStateAction } from 'react'

import { applyRoomEvent, emptyBoard, parsePossibleActions } from '../board/applyEvent'
import { wsUrl } from '../net/wsUrl'
import type { BoardSnapshot, LogEntry, PendingRequest, Phase, WireAction } from '../types'

const CAPACITY = 4

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
  const [bots, setBots] = useState(0)
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
  const botsRef = useRef(0)
  const meSeatRef = useRef(0)

  useEffect(() => { playerIdRef.current = playerId }, [playerId])
  useEffect(() => { roomIdRef.current = roomId }, [roomId])
  useEffect(() => { botsRef.current = bots }, [bots])
  useEffect(() => { meSeatRef.current = board.meSeat }, [board.meSeat])

  const nextReq = () => {
    const id = reqIdRef.current
    reqIdRef.current += 1
    return id
  }

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
        setBots(0)
        setStatus(`已创建 room ${msg.room_id as number}`)
        break
      case 'room_joined':
        setRoomId(msg.room_id as number)
        setStatus(`已加入 room ${msg.room_id as number}`)
        break
      case 'bot_added':
        setBots((n) => n + 1)
        break
      case 'bot_removed':
        setBots((n) => Math.max(0, n - 1))
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
  }, [closeLobby, connectRoom])

  const connectLobby = useCallback(() => {
    closeLobby()
    closeRoom()
    setBoard(emptyBoard())
    setPending(null)
    setRoomId(null)
    setBots(0)
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
  }, [closeLobby, closeRoom, handleLobbyMessage, phase])

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

      for (let i = 0; i < CAPACITY - 1; i++) {
        sendLobby({ type: 'add_bot', request_id: nextReq(), room_id: rid })
        await waitType(['bot_added'])
      }
      setBots(CAPACITY - 1)
      botsRef.current = CAPACITY - 1

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

  const occupied = (roomId != null ? 1 + bots : 0)

  return {
    phase,
    playerId,
    roomId,
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
    addBot,
    startGame,
    quickStart,
    submitAction,
    closeAll: () => {
      closeLobby()
      closeRoom()
      setPhase('idle')
      setStatus('已断开')
    },
  }
}
