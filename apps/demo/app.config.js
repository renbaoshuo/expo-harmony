'use strict';

module.exports = ({ config }) => {
  const signingConfigFile = process.env.EXPO_HARMONY_SIGNING_CONFIG_FILE;
  return {
    ...config,
    harmony: {
      ...config.harmony,
      ...(signingConfigFile ? { signingConfigFile } : {}),
    },
  };
};
