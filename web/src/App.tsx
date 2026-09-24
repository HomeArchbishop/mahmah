import { useMemo, useState } from 'react'

import { findDahaiAction } from './board/applyEvent'
import { BoardView } from './components/BoardView'
import { TestDock } from './components/TestDock'
import { useTestSession } from './hooks/useTestSession'
import type { Pai, WireAction } from './types'

function btnClass (enabled: boolean) {
  return [
    'rounded border px-2 py-1 text-[0.7rem]',
    enabled
      ? 'border-gray-600 text-gray-300 hover:border-gray-400 hover:text-gray-100'
      : 'cursor-not-allowed border-gray-800 text-gray-700',
  ].join(' ')
}

export default function App () {
  const s = useTestSession()
  const [joinId, setJoinId] = useState('')

  const playable = useMemo(() => {
    const set = new Set<Pai>()
    if (!s.pending) return set
    for (const a of s.pending.actions) {
      if (a.type === 'dahai' && typeof a.pai === 'string') set.add(a.pai as Pai)
    }
    return set
  }, [s.pending])

  const onDiscard = (pai: Pai, tsumogiri: boolean) => {
    if (!s.pending) return
    const action = findDahaiAction(s.pending.actions, pai, tsumogiri)
    if (action) s.submitAction(action)
  }

  const onAction = (a: WireAction) => s.submitAction(a)

  const waitingHint =
    s.phase === 'room' && !s.pending
      ? '等待其他座位（超时会摸切/过）'
      : s.phase === 'lobby'
        ? s.roomId != null
          ? (s.isHost ? '房主：加 bot 或等人满后开局' : '等待房主开局…')
          : '创建房间或输入 room_id 加入'
        : null

  const lobbyOk = s.lobbyConnected
  const inLobby = s.phase === 'lobby' && lobbyOk
  const hostOk = inLobby && s.isHost && s.roomId != null

  return (
    <div className='flex min-h-screen flex-col bg-table text-gray-300'>
      <header className='flex shrink-0 flex-wrap items-center justify-between gap-2 px-4 py-2 text-[0.7rem] text-gray-600'>
        <div className='flex flex-wrap items-center gap-2'>
          <span className='text-gray-400'>mahmah · 人工测试</span>
          <span className='text-gray-700'>|</span>
          <span>{s.status}</span>
          {s.playerId != null && <span>player {s.playerId}</span>}
          {s.roomId != null && <span>room {s.roomId}</span>}
          {s.roomId != null && (
            <span className={s.isHost ? 'text-amber-600' : 'text-gray-600'}>
              {s.isHost ? 'host' : 'guest'}
            </span>
          )}
          {s.roomId != null && <span>席位 {s.occupied}/4（bot {s.bots}）</span>}
        </div>
        <div className='flex flex-wrap items-center gap-1.5'>
          <button type='button' className={btnClass(true)} onClick={s.connectLobby}>
            连 Lobby
          </button>
          <button
            type='button'
            className={btnClass(inLobby && !s.busy && s.roomId == null)}
            disabled={!inLobby || s.busy || s.roomId != null}
            onClick={() => { void s.quickStart() }}
          >
            一键开桌
          </button>
          <button
            type='button'
            className={btnClass(inLobby && s.roomId == null)}
            disabled={!inLobby || s.roomId != null}
            onClick={s.createRoom}
          >
            创建
          </button>
          <input
            type='text'
            inputMode='numeric'
            placeholder='room id'
            value={joinId}
            onChange={(e) => setJoinId(e.target.value)}
            className='w-16 rounded border border-gray-800 bg-transparent px-1.5 py-1 text-[0.7rem] text-gray-300 outline-none placeholder:text-gray-700 focus:border-gray-600'
            disabled={!inLobby || s.roomId != null}
          />
          <button
            type='button'
            className={btnClass(inLobby && s.roomId == null && joinId.trim() !== '')}
            disabled={!inLobby || s.roomId != null || joinId.trim() === ''}
            onClick={() => s.joinRoom(Number(joinId.trim()))}
          >
            加入
          </button>
          <button
            type='button'
            className={btnClass(hostOk && s.occupied < 4)}
            disabled={!hostOk || s.occupied >= 4}
            onClick={s.addBot}
          >
            加 Bot
          </button>
          <button
            type='button'
            className={btnClass(hostOk && s.occupied >= 4)}
            disabled={!hostOk || s.occupied < 4}
            onClick={s.startGame}
          >
            开始
          </button>
          <button type='button' className={btnClass(true)} onClick={s.closeAll}>
            断开
          </button>
          <span className={s.roomConnected || s.lobbyConnected ? 'text-emerald-700' : 'text-gray-700'}>
            {s.roomConnected ? 'room' : s.lobbyConnected ? 'lobby' : '离线'}
          </span>
        </div>
      </header>

      <main className='flex min-h-0 flex-1 flex-col'>
        <BoardView
          snapshot={s.board}
          playable={playable}
          onDiscard={onDiscard}
        />
      </main>

      <TestDock
        pending={s.pending}
        logs={s.logs}
        waitingHint={waitingHint}
        onAction={onAction}
      />
    </div>
  )
}
