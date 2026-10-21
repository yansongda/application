import localUnitTest from './LocalUnit.test';
import appLockPolicyTest from './AppLockPolicy.test';
import itemFilterTest from './ItemFilter.test';

export default function testsuite() {
  localUnitTest();
  appLockPolicyTest();
  itemFilterTest();
}
