/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as StoreReview from 'expo-store-review';

import { json } from '../format';
import { ActionButton, ActionRow, Panel, ResultPanel, useAsyncResult } from '../ui';

export function StoreReviewDemo() {
  const status = useAsyncResult();
  const review = useAsyncResult();
  const busy = status.state.phase === 'running' || review.state.phase === 'running';

  return (
    <>
      <Panel title="应用商店">
        <ActionRow>
          <ActionButton disabled={busy} label="查询应用内评价是否可用" onPress={() => void status.run(async () => String(await StoreReview.isAvailableAsync()))} testID="store-review-inspect" />
          <ActionButton disabled={busy} label="查询是否有评价入口" onPress={() => void status.run(async () => String(await StoreReview.hasAction()))} tone="secondary" />
          <ActionButton disabled={busy} label="读取商店链接" onPress={() => void status.run(() => json(StoreReview.storeUrl()))} tone="secondary" />
        </ActionRow>
        <ResultPanel state={status.state} />
      </Panel>
      <Panel title="应用内评价">
        <ActionButton
          disabled={busy}
          label="请求应用内评价"
          onPress={() => void review.run(async () => {
            await StoreReview.requestReview();
            return '评价请求已返回';
          })}
          testID="store-review-request"
        />
        <ResultPanel state={review.state} />
      </Panel>
    </>
  );
}
