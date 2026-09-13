import type { Pai, PlayerSnapshot, TableSide } from '../types'
import { flexBoxClass, HALF_GAP } from '../layout/table'
import { Hand } from './Hand'
import { Melds } from './Meld'

export function Seat ({
  player,
  side,
  isMe,
  playable,
  onDiscard,
}: {
  player: PlayerSnapshot
  side: TableSide
  isMe: boolean
  playable?: Set<Pai>
  onDiscard?: (pai: Pai, tsumogiri: boolean) => void
}) {
  const melds = [...player.furo, ...player.ankan].reverse()

  return (
    <div className={flexBoxClass(side)} style={{ gap: HALF_GAP }}>
      <div className='relative inline-flex shrink-0'>
        <Hand
          side={side}
          tehai={player.tehai}
          tsumoPai={player.tsumoPai}
          hidden={!isMe}
          playable={isMe ? playable : undefined}
          onDiscard={isMe ? onDiscard : undefined}
          reachHandLayIndex={
            player.reached && player.reachRiverIndex === null
              ? player.reachHandLayIndex
              : null
          }
        />
      </div>
      <Melds side={side} melds={melds} />
    </div>
  )
}
