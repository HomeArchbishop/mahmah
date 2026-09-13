import type { LogEntry, Pai, PendingRequest, WireAction } from '../types'
import { formatPaiLabel } from '../utils/paiToTile'

function actionLabel (a: WireAction): string {
  if (a.type === 'dahai' && typeof a.pai === 'string') {
    const t = a.tsumogiri ? '摸切' : '手切'
    return `打 ${formatPaiLabel(a.pai as Pai)} (${t})`
  }
  if (a.type === 'none') return '过'
  if (a.type === 'pon') return '碰'
  if (a.type === 'chi') return '吃'
  if (a.type === 'daiminkan') return '大明杠'
  if (a.type === 'ankan') return '暗杠'
  if (a.type === 'kakan') return '加杠'
  if (a.type === 'reach') return '立直'
  if (a.type === 'hora') return '和'
  if (a.type === 'ryukyoku') return '流局'
  return a.type
}

export function TestDock ({
  pending,
  logs,
  waitingHint,
  onAction,
}: {
  pending: PendingRequest | null
  logs: LogEntry[]
  waitingHint: string | null
  onAction: (a: WireAction) => void
}) {
  return (
    <footer className='shrink-0 border-t border-gray-800/60 bg-hub/80 px-4 py-2 text-xs text-gray-500'>
      <div className='mb-2 flex flex-wrap items-center gap-2'>
        {pending
          ? (
              <>
                <span className='text-gray-400'>
                  请出招 · req {pending.requestId}
                  {pending.deadlineMs != null ? ` · ${pending.deadlineMs}ms` : ''}
                </span>
                {pending.actions.map((a, i) => (
                  <button
                    key={i}
                    type='button'
                    className='rounded border border-gray-700 bg-gray-900 px-2 py-1 text-gray-200 hover:border-amber-500/60 hover:text-amber-100'
                    onClick={() => onAction(a)}
                  >
                    {actionLabel(a)}
                  </button>
                ))}
              </>
            )
          : (
              <span className='text-gray-600'>{waitingHint ?? '等待 request_action…'}</span>
            )}
      </div>
      <div className='max-h-28 overflow-y-auto font-mono text-[0.65rem] leading-relaxed text-gray-600'>
        {[...logs].reverse().map((e) => (
          <div key={e.id}>
            <span className='text-gray-700'>
              {e.dir === 'in' ? '←' : e.dir === 'out' ? '→' : '·'} {e.channel}{' '}
            </span>
            <span className={e.dir === 'out' ? 'text-sky-700' : e.dir === 'in' ? 'text-gray-500' : 'text-gray-600'}>
              {e.text}
            </span>
          </div>
        ))}
      </div>
    </footer>
  )
}
