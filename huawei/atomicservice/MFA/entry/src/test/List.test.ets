import localUnitTest from './LocalUnit.test';
import appLockPolicyTest from './AppLockPolicy.test';

export default function testsuite() {
  localUnitTest();
  appLockPolicyTest();
}
