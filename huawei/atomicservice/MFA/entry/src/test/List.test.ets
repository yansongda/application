import localUnitTest from './LocalUnit.test';
import appLockPolicyTest from './AppLockPolicy.test';
import authStatePolicyTest from './AuthStatePolicy.test';
import backupTest from './Backup.test';
import itemFilterTest from './ItemFilter.test';
import listViewStateTest from './ListViewState.test';
import otpSecretStrictTest from './OtpSecretStrict.test';
import sessionThrottleTest from './SessionThrottle.test';
import singleFlightTest from './SingleFlight.test';
import windowCoordinatorTest from './WindowCoordinator.test';

export default function testsuite() {
  localUnitTest();
  appLockPolicyTest();
  authStatePolicyTest();
  backupTest();
  itemFilterTest();
  listViewStateTest();
  otpSecretStrictTest();
  sessionThrottleTest();
  singleFlightTest();
  windowCoordinatorTest();
}
