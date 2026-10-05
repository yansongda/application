import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // 测试套件：参数为套件名与套件函数。
    beforeAll(() => {
      // 仅在所有用例开始前执行一次；仅接受一个参数：预置函数。
    });
    beforeEach(() => {
      // 在每个用例开始前执行，执行次数与 it 定义的用例数相同；仅接受一个参数：预置函数。
    });
    afterEach(() => {
      // 在每个用例结束后执行，执行次数与 it 定义的用例数相同；仅接受一个参数：清理函数。
    });
    afterAll(() => {
      // 仅在所有用例结束后执行一次；仅接受一个参数：清理函数。
    });
    it('assertContain', 0, () => {
      // 用例：接受三个参数——用例名、过滤参数、用例函数。
      let a = 'abc';
      let b = 'b';
      // 断言方法：声明期望的布尔条件。
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
  });
}