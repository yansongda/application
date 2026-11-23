import { describe, expect, it } from '@ohos/hypium';
import { SingleFlight } from '../main/ets/utils/SingleFlight';

export default function singleFlightTest(): void {
  describe('singleFlight', () => {
    it('run_shares_in_flight_task', 0, async () => {
      const flight: SingleFlight<number> = new SingleFlight<number>();
      let calls: number = 0;
      const task = (): Promise<number> => {
        calls++;

        return Promise.resolve(calls);
      };

      const first: Promise<number> = flight.run(task);
      const second: Promise<number> = flight.run(task);

      expect(flight.busy).assertTrue();
      expect(await first).assertEqual(1);
      expect(await second).assertEqual(1);
      // 共享而不是重复执行
      expect(calls).assertEqual(1);
      expect(flight.busy).assertFalse();
    });

    it('enqueue_runs_again_after_current', 0, async () => {
      const flight: SingleFlight<number> = new SingleFlight<number>();
      let calls: number = 0;
      const task = (): Promise<number> => {
        calls++;

        return Promise.resolve(calls);
      };

      const first: Promise<number> = flight.run(task);
      const second: Promise<number> = flight.enqueue(task);

      expect(await first).assertEqual(1);
      expect(await second).assertEqual(2);
      expect(calls).assertEqual(2);
      expect(flight.busy).assertFalse();
    });

    it('busy_is_cleared_on_rejection', 0, async () => {
      const flight: SingleFlight<number> = new SingleFlight<number>();
      const failed: Promise<number> = flight.run((): Promise<number> => Promise.reject(new Error('boom')));

      // 显式消费 rejection：单飞状态必须复位，否则后续调用全被挡住
      await failed.then((): void => {
      }, (): void => {
      });

      expect(flight.busy).assertFalse();
    });

    it('enqueue_survives_rejected_current', 0, async () => {
      const flight: SingleFlight<number> = new SingleFlight<number>();
      const first: Promise<number> = flight.run((): Promise<number> => Promise.reject(new Error('boom')));
      const second: Promise<number> = flight.enqueue((): Promise<number> => Promise.resolve(7));

      await first.then((): void => {
      }, (): void => {
      });

      // 前一个任务失败不阻塞排队的那次
      expect(await second).assertEqual(7);
      expect(flight.busy).assertFalse();
    });
  });
}
