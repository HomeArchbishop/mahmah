import type { Pai, TableSide } from '../types'
import { tileCell, tileImgDeg } from '../layout/table'
import { paiToTileSrc } from '../utils/paiToTile'

interface TileProps {
  pai: Pai
  side: TableSide
  lay?: boolean
  hidden?: boolean
  /** 可点选（自家合法着） */
  interactive?: boolean
  highlighted?: boolean
  onSelect?: () => void
}

export function Tile ({
  pai,
  side,
  lay = false,
  hidden = false,
  interactive = false,
  highlighted = false,
  onSelect,
}: TileProps) {
  const deg = tileImgDeg(side, lay)
  const src = paiToTileSrc(hidden ? '?' : pai)

  const className = [
    'inline-flex shrink-0 items-center justify-center',
    tileCell(deg),
    interactive ? 'cursor-pointer transition-transform hover:-translate-y-1' : '',
    highlighted ? 'ring-2 ring-amber-400/80 rounded-[4px]' : '',
  ].filter(Boolean).join(' ')

  return (
    <span
      className={className}
      role={interactive ? 'button' : undefined}
      tabIndex={interactive ? 0 : undefined}
      onClick={interactive ? onSelect : undefined}
      onKeyDown={interactive
        ? (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault()
              onSelect?.()
            }
          }
        : undefined}
    >
      <img
        src={src}
        alt={pai}
        className='h-7 w-5 rounded-[4px] object-contain'
        style={{ transform: `rotate(${deg}deg)` }}
        draggable={false}
      />
    </span>
  )
}
