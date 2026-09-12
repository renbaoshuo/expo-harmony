import Constants from 'expo-constants';
import { File, Paths } from 'expo-file-system';

export type BackgroundExecution = {
  count: number;
  error: string | null;
  eventId: string;
  headless: boolean;
  occurredAt: string;
};

export function readExecution(task: string): BackgroundExecution | null {
  const file = new File(Paths.document, `${task}.json`);
  if (!file.exists) return null;

  return JSON.parse(file.textSync()) as BackgroundExecution;
}

export function recordExecution(task: string, eventId: string, error: string | null): BackgroundExecution {
  const previous = readExecution(task);
  const value = {
    count: (previous?.count ?? 0) + 1,
    error,
    eventId,
    headless: Constants.isHeadless,
    occurredAt: new Date().toISOString(),
  };

  new File(Paths.document, `${task}.json`).write(JSON.stringify(value));
  console.info(`Expo demo background execution: ${task} ${JSON.stringify(value)}`);

  return value;
}
