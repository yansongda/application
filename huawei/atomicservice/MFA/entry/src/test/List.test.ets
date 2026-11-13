import localUnitTest from './LocalUnit.test';
import appLockPolicyTest from './AppLockPolicy.test';
import backupTest from './Backup.test';
import itemFilterTest from './ItemFilter.test';
import listViewStateTest from './ListViewState.test';
import otpSecretStrictTest from './OtpSecretStrict.test';

export default function testsuite() {
  localUnitTest();
  appLockPolicyTest();
  backupTest();
  itemFilterTest();
  listViewStateTest();
  otpSecretStrictTest();
}
