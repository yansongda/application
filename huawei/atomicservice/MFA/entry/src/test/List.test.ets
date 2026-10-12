import localUnitTest from './LocalUnit.test';
import lockPolicyTest from './LockPolicy.test';

export default function testsuite() {
  localUnitTest();
  lockPolicyTest();
}
