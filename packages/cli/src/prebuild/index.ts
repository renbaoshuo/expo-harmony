import { parseCommandArgs, type Command } from '../command';
import { HarmonyCliError } from '../errors';
import { withHarmonyProjectLockAsync } from '../projectLock';
import { parsePrebuildArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(args => parsePrebuildArgs(args, { allowProject: true }), argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const { check, clean, passthrough } = options;

  if (check && passthrough.length) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--check cannot be combined with mutating prebuild options.');
  }

  return withHarmonyProjectLockAsync(
    root,
    check ? 'prebuild-check' : 'prebuild',
    async () => {
      if (clean) {
        const { assertSafeCleanTarget } = await import('./clean.js');
        await assertSafeCleanTarget(root);
      }

      const { doctorAsync, formatDoctor } = await import('../doctor/doctor.js');
      const doctor = await doctorAsync(root, {
        requireBuildTools: false,
        validateGeneratedProject: !clean,
        validateModules: false,
      });
      if (!doctor.ok) {
        io.error(formatDoctor(doctor));
        throw new HarmonyCliError('ERR_HARMONY_DOCTOR_FAILED', 'Harmony doctor found blocking errors.', {
          operation: 'doctor',
        });
      }

      for (const item of doctor.checks.filter(item => item.status === 'warn')) io.warn(`! ${item.message}`);

      if (check) {
        const { checkAsync } = await import('./check.js');
        const result = await checkAsync(root);

        if (result.clean) io.log('Harmony CNG output is up to date.');
        else for (const change of result.changes) io.log(`${change.type}: ${change.path}`);

        return result.clean ? 0 : 2;
      }

      const { prebuildParsedAsync } = await import('./prebuild.js');
      await prebuildParsedAsync(root, passthrough);

      return 0;
    });
};
