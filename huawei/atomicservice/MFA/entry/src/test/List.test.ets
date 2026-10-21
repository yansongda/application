import localUnitTest from './LocalUnit.test';
import appLockPolicyTest from './AppLockPolicy.test';
import itemFilterTest from './ItemFilter.test';
import listViewStateTest from './ListViewState.test';

export default function testsuite() {
  localUnitTest();
  appLockPolicyTest();
  itemFilterTest();
  listViewStateTest();
}
