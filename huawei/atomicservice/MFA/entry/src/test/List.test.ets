import localUnitTest from './LocalUnit.test';
import appLockPolicyTest from './AppLockPolicy.test';
import itemFilterTest from './ItemFilter.test';
import listViewStateTest from './ListViewState.test';
import otpSecretStrictTest from './OtpSecretStrict.test';
import envelopeTest from './Envelope.test';
import payloadTest from './Payload.test';
import importPlanTest from './ImportPlan.test';

export default function testsuite() {
  localUnitTest();
  appLockPolicyTest();
  itemFilterTest();
  listViewStateTest();
  otpSecretStrictTest();
  envelopeTest();
  payloadTest();
  importPlanTest();
}
