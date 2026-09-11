import { parseCommandArgs, type Command } from '../command';
import { parseDoctorArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(parseDoctorArgs, argv, io);
  if (!args) return 0;

  const { projectRoot: root } = args;
  const { doctorAsync, formatDoctor } = await import('./doctor.js');

  const result = await doctorAsync(root, { requireBuildTools: true });

  io.log(formatDoctor(result));

  return result.ok ? 0 : 1;
};
