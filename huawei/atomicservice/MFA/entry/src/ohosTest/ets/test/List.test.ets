import abilityTest from './Ability.test';
import totpDeviceTest from './TotpDevice.test';
import backupCryptoTest from './BackupCrypto.test';

export default function testsuite() {
  abilityTest();
  totpDeviceTest();
  backupCryptoTest();
}