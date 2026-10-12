import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Keep device-specific credentials outside the shared project and customer export.
hvigor.getRootNode().afterNodeEvaluate((node) => {
  const context = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  if (context.getBuildMode() !== 'debug') {
    return;
  }
  const profile = context.getBuildProfileOpt();
  const productName = context.getCurrentProduct().getProductName();
  const product = profile.app.products?.find((item) => item.name === productName);
  // A signature configured through DevEco takes precedence over the local backup.
  if (!product || product.signingConfig || profile.app.signingConfigs?.length) {
    return;
  }
  const localPath = resolve(context.getProjectPath(), '.local/build-profile.signing.json5');
  if (!existsSync(localPath)) {
    return;
  }
  let local: ReturnType<OhosAppContext['getBuildProfileOpt']>;
  try {
    local = JSON.parse(readFileSync(localPath, 'utf8'));
  } catch {
    throw new Error('Invalid local signing backup; configure Signing Configs in DevEco.');
  }
  const localProduct = local.app?.products?.find((item) => item.name === productName);
  const signature = local.app?.signingConfigs?.find((item) => item.name === localProduct?.signingConfig);
  if (!signature || ![signature.material?.storeFile, signature.material?.certpath,
    signature.material?.profile].every((path) => typeof path === 'string' && existsSync(path))) {
    throw new Error('Local signing files are missing; configure Signing Configs in DevEco.');
  }
  profile.app.signingConfigs = [signature];
  product.signingConfig = signature.name;
  context.setBuildProfileOpt(profile);
});

export default {
  system: appTasks,
  plugins: []
};
