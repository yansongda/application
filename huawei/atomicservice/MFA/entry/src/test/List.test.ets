import localUnitTest from './LocalUnit.test';
import totpCodeTest from './TotpCode.test';

export default function testsuite() {
  localUnitTest();
  totpCodeTest();
}