import type { ReactNode } from 'react'
import type { Pai, TableSide } from '../types'
import { flexDir, GAP, HALF_GAP, handLayout, tileCell, tileImgDeg } from '../layout/table'
import { sortedTehai } from '../utils/sortPai'
import { Tile } from './Tile'

interface HandProps {
  side: TableSide
  tehai: Pai[]
  tsumoPai?: Pai | null
  hidden?: boolean
  reachHandLayIndex?: number | null
  /** 可打的牌面（来自 possible_actions） */
  playable?: Set<Pai>
  onDiscard?: (pai: Pai, tsumogiri: boolean) => void
}

function HandStrip ({
  dir,
  rev,
  gap,
  children,
}: {
  dir: 'row' | 'col'
  rev?: boolean
  gap?: string
  children: ReactNode
}) {
  return (
    <div
      className={`flex flex-nowrap items-end ${flexDir(dir, rev ?? false)}`}
      style={{ gap }}
    >
      {children}
    </div>
  )
}

export function Hand ({
  side,
  tehai,
  tsumoPai = null,
  hidden = false,
  reachHandLayIndex = null,
  playable,
  onDiscard,
}: HandProps) {
  const hand = handLayout(side)
  const hasTsumo = tsumoPai !== null
  const interactive = !hidden && playable !== undefined && onDiscard !== undefined
  const { body, tsumo } = hidden
    ? {
        body: Array.from(
          { length: hasTsumo ? Math.max(0, tehai.length - 1) : tehai.length },
          () => '?' as Pai,
        ),
        tsumo: hasTsumo ? ('?' as Pai) : null,
      }
    : sortedTehai(tehai, tsumoPai)

  if (body.length === 0 && tsumo === null) {
    return null
  }

  const canPlay = (pai: Pai) => interactive && playable.has(pai)

  const bodyStrip = body.length > 0
    ? (
        <HandStrip dir={hand.dir} rev={hand.rev} gap={GAP}>
          {body.map((pai, i) => (
            <Tile
              key={i}
              pai={pai}
              side={side}
              hidden={hidden}
              lay={reachHandLayIndex !== null && i === reachHandLayIndex}
              interactive={canPlay(pai)}
              highlighted={canPlay(pai)}
              onSelect={() => onDiscard?.(pai, false)}
            />
          ))}
        </HandStrip>
      )
    : null

  const tsumoStrip = (
    <HandStrip dir={hand.dir} gap={GAP}>
      {tsumo !== null
        ? (
            <Tile
              pai={tsumo}
              side={side}
              hidden={hidden}
              interactive={canPlay(tsumo)}
              highlighted={canPlay(tsumo)}
              onSelect={() => onDiscard?.(tsumo, true)}
            />
          )
        : (
            <span
              className='inline-flex shrink-0 flex-col items-center justify-end'
              aria-hidden
            >
              <span className={tileCell(tileImgDeg(side, false))} />
            </span>
          )}
    </HandStrip>
  )

  if (bodyStrip === null) {
    return tsumoStrip
  }

  const ordered = hand.tsumoInside
    ? <>{bodyStrip}{tsumoStrip}</>
    : <>{tsumoStrip}{bodyStrip}</>

  return (
    <div
      className={`flex shrink-0 items-end ${flexDir(hand.dir, false)}`}
      style={{ gap: HALF_GAP }}
    >
      {ordered}
    </div>
  )
}
