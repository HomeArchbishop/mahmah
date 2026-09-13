import type { BoardSnapshot, MeldSnapshot, Pai, PlayerSnapshot, RoundSnapshot, WireAction } from '../types'

function emptyPlayer (seat: number): PlayerSnapshot {
  return {
    seat,
    tehai: [],
    tsumoPai: null,
    sutehai: [],
    furo: [],
    ankan: [],
    reached: false,
    reachHandLayIndex: null,
    reachRiverIndex: null,
    nuki: [],
  }
}

function ensureRound (board: BoardSnapshot, oya = 0): RoundSnapshot {
  if (board.round) return board.round
  return {
    bakaze: 'E',
    kyoku: 1,
    honba: 0,
    kyotaku: 0,
    oya,
    tilesLeft: 70,
    doraMarkers: [],
    scores: [25000, 25000, 25000, 25000],
    players: [0, 1, 2, 3].map(emptyPlayer),
  }
}

function clonePlayer (p: PlayerSnapshot): PlayerSnapshot {
  return {
    ...p,
    tehai: [...p.tehai],
    sutehai: [...p.sutehai],
    furo: p.furo.map((m) => ({ ...m, tiles: [...m.tiles] })),
    ankan: p.ankan.map((m) => ({ ...m, tiles: [...m.tiles] })),
    nuki: [...p.nuki],
  }
}

function withSeats (
  round: RoundSnapshot,
  seats: number[],
  mutate: (players: PlayerSnapshot[]) => void,
): RoundSnapshot {
  const players = round.players.map((p) =>
    seats.includes(p.seat) ? clonePlayer(p) : p,
  )
  mutate(players)
  return { ...round, players }
}

function asPai (v: unknown): Pai {
  return (typeof v === 'string' ? v : '?') as Pai
}

function asPaiList (v: unknown): Pai[] {
  if (!Array.isArray(v)) return []
  return v.map(asPai)
}

function sameKind (a: Pai, b: Pai): boolean {
  if (a === b) return true
  const norm = (p: Pai) =>
    (p.length >= 3 && p.endsWith('r') ? p.slice(0, -1) : p) as Pai
  return norm(a) === norm(b)
}

/** 从手牌移除；无精确牌则扣 "?"（他家遮罩）。 */
function removeFromTehai (tehai: Pai[], tiles: Pai[]): Pai[] {
  const next = [...tehai]
  for (const t of tiles) {
    let j = next.lastIndexOf(t)
    if (j < 0) j = next.lastIndexOf('?')
    if (j >= 0) next.splice(j, 1)
  }
  return next
}

function popRiver (sutehai: Pai[], pai: Pai): Pai[] {
  const next = [...sutehai]
  for (let i = next.length - 1; i >= 0; i--) {
    if (next[i] === pai || next[i] === '?') {
      next.splice(i, 1)
      return next
    }
  }
  if (next.length > 0) next.pop()
  return next
}

/**
 * 鸣牌横牌位置：相对 actor，target 为上家→0、对家→1、下家→末张。
 * rel = (target - actor + 4) % 4：1=下家 2=对家 3=上家。
 */
function calledIndex (actor: number, target: number, len: number): number {
  const rel = (target - actor + 4) % 4
  if (rel === 1) return len - 1
  if (rel === 2) return Math.min(1, len - 1)
  return 0
}

function buildOpenMeld (pai: Pai, consumed: Pai[], actor: number, target: number): MeldSnapshot {
  const len = consumed.length + 1
  const idx = calledIndex(actor, target, len)
  const tiles = [...consumed]
  tiles.splice(idx, 0, pai)
  return { tiles, calledIndex: idx, concealed: false }
}

/** 用 MJAI 事件增量更新牌桌 */
export function applyRoomEvent (board: BoardSnapshot, msg: Record<string, unknown>): BoardSnapshot {
  const type = msg.type
  if (typeof type !== 'string') return board

  switch (type) {
    case 'start_game': {
      const id = typeof msg.id === 'number' ? msg.id : board.meSeat
      return { ...board, meSeat: id, round: ensureRound({ ...board, meSeat: id }) }
    }
    case 'start_kyoku': {
      const oya = typeof msg.oya === 'number' ? msg.oya : 0
      let round = ensureRound(board, oya)
      round = {
        ...round,
        oya,
        bakaze: (typeof msg.bakaze === 'string' ? msg.bakaze : round.bakaze) as RoundSnapshot['bakaze'],
        kyoku: typeof msg.kyoku === 'number' ? msg.kyoku : round.kyoku,
        honba: typeof msg.honba === 'number' ? msg.honba : round.honba,
        kyotaku: typeof msg.kyotaku === 'number' ? msg.kyotaku : round.kyotaku,
        tilesLeft: 70,
        doraMarkers: Array.isArray(msg.dora_marker)
          ? (msg.dora_marker as Pai[])
          : typeof msg.dora_marker === 'string'
            ? [msg.dora_marker as Pai]
            : [],
        scores: Array.isArray(msg.scores) ? (msg.scores as number[]) : round.scores,
        players: [0, 1, 2, 3].map(emptyPlayer),
      }
      if (Array.isArray(msg.tehais)) {
        const tehais = msg.tehais as unknown[]
        round = {
          ...round,
          players: round.players.map((p, i) => ({
            ...p,
            tehai: Array.isArray(tehais[i]) ? (tehais[i] as Pai[]) : [],
          })),
        }
      }
      return { ...board, round }
    }
    case 'tsumo': {
      const actor = msg.actor as number
      const pai = asPai(msg.pai)
      const round = ensureRound(board)
      return {
        ...board,
        round: {
          ...withSeats(round, [actor], (ps) => {
            const p = ps[actor]!
            p.tsumoPai = pai
            p.tehai = [...p.tehai, pai]
          }),
          tilesLeft: Math.max(0, round.tilesLeft - 1),
        },
      }
    }
    case 'dahai': {
      const actor = msg.actor as number
      const pai = asPai(msg.pai)
      const tsumogiri = Boolean(msg.tsumogiri)
      const round = ensureRound(board)
      return {
        ...board,
        round: withSeats(round, [actor], (ps) => {
          const p = ps[actor]!
          if (tsumogiri && p.tsumoPai !== null) {
            const drop = p.tsumoPai
            const i = p.tehai.lastIndexOf(drop)
            if (i >= 0) p.tehai.splice(i, 1)
            else if (drop === '?') p.tehai.pop()
          } else {
            p.tehai = removeFromTehai(p.tehai, [pai])
          }
          p.tsumoPai = null
          p.sutehai = [...p.sutehai, pai]
          if (p.reached && p.reachRiverIndex === null) {
            p.reachRiverIndex = p.sutehai.length - 1
          }
        }),
      }
    }
    case 'chi':
    case 'pon':
    case 'daiminkan': {
      const actor = msg.actor as number
      const target = msg.target as number
      const pai = asPai(msg.pai)
      const consumed = asPaiList(msg.consumed)
      const round = ensureRound(board)
      const meld = buildOpenMeld(pai, consumed, actor, target)
      return {
        ...board,
        round: withSeats(round, [actor, target], (ps) => {
          const a = ps[actor]!
          const t = ps[target]!
          a.tehai = removeFromTehai(a.tehai, consumed)
          a.tsumoPai = null
          a.furo = [...a.furo, meld]
          t.sutehai = popRiver(t.sutehai, pai)
        }),
      }
    }
    case 'ankan': {
      const actor = msg.actor as number
      const consumed = asPaiList(msg.consumed)
      const round = ensureRound(board)
      const meld: MeldSnapshot = {
        tiles: consumed.length === 4 ? consumed : [...consumed, ...Array(4 - consumed.length).fill('?') as Pai[]],
        calledIndex: -1,
        concealed: true,
      }
      return {
        ...board,
        round: withSeats(round, [actor], (ps) => {
          const p = ps[actor]!
          p.tehai = removeFromTehai(p.tehai, consumed)
          p.tsumoPai = null
          p.ankan = [...p.ankan, meld]
        }),
      }
    }
    case 'kakan': {
      const actor = msg.actor as number
      const pai = asPai(msg.pai)
      const round = ensureRound(board)
      return {
        ...board,
        round: withSeats(round, [actor], (ps) => {
          const p = ps[actor]!
          p.tehai = removeFromTehai(p.tehai, [pai])
          p.tsumoPai = null
          const fi = p.furo.findIndex(
            (m) => !m.concealed && m.tiles.length === 3 && m.tiles.some((t) => sameKind(t, pai)),
          )
          if (fi >= 0) {
            const m = p.furo[fi]!
            p.furo = p.furo.map((x, i) =>
              i === fi ? { ...m, tiles: [...m.tiles, pai] } : x,
            )
          } else {
            p.furo = [
              ...p.furo,
              { tiles: [pai, pai, pai, pai], calledIndex: 1, concealed: false },
            ]
          }
        }),
      }
    }
    case 'dora': {
      const round = ensureRound(board)
      const marker = asPai(msg.dora_marker)
      return {
        ...board,
        round: { ...round, doraMarkers: [...round.doraMarkers, marker] },
      }
    }
    case 'reach': {
      const actor = msg.actor as number
      const round = ensureRound(board)
      return {
        ...board,
        round: withSeats(round, [actor], (ps) => {
          const p = ps[actor]!
          p.reached = true
          // 宣言后下一打为立直宣言牌；横牌索引暂取摸牌位（末张）
          p.reachHandLayIndex = Math.max(0, p.tehai.length - 1)
          p.reachRiverIndex = null
        }),
      }
    }
    case 'reach_accepted': {
      const actor = msg.actor as number
      const round = ensureRound(board)
      return {
        ...board,
        round: withSeats(round, [actor], (ps) => {
          ps[actor]!.reached = true
        }),
      }
    }
    case 'hora':
    case 'end_kyoku':
      return board
    case 'ryukyoku':
    case 'end_game': {
      const round = board.round
      if (!round) return board
      if (type === 'end_game' && Array.isArray(msg.scores)) {
        return { ...board, round: { ...round, scores: msg.scores as number[] } }
      }
      return board
    }
    default:
      return board
  }
}

export function parsePossibleActions (raw: unknown): WireAction[] {
  if (!Array.isArray(raw)) return []
  return raw.filter((a): a is WireAction => a !== null && typeof a === 'object' && typeof (a as WireAction).type === 'string')
}

/** 点牌时在 possible_actions 里找匹配的 dahai */
export function findDahaiAction (
  actions: WireAction[],
  pai: Pai,
  tsumogiri: boolean,
): WireAction | null {
  const exact = actions.find(
    (a) => a.type === 'dahai' && a.pai === pai && (a.tsumogiri ?? false) === tsumogiri,
  )
  if (exact) return exact
  return actions.find((a) => a.type === 'dahai' && a.pai === pai) ?? null
}

export function emptyBoard (): BoardSnapshot {
  return { meSeat: 0, round: null }
}
