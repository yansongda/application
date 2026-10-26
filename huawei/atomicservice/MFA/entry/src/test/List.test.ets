import localUnitTest from './LocalUnit.test';
import appLockPolicyTest from './AppLockPolicy.test';
import base32Test from './Base32.test';
import itemFilterTest from './ItemFilter.test';
import listViewStateTest from './ListViewState.test';

export default function testsuite() {
  localUnitTest();
  appLockPolicyTest();
  base32Test();
  itemFilterTest();
  listViewStateTest();
}
