import fs from '@ohos.file.fs';
import { ExpoService, ExpoServiceKey } from './ExpoServicesRegistry';

export interface ExpoRuntimeDirectories {
  directory(base: string): string;
  preferenceName(name: string): string;
}

export const ExpoRuntimeDirectoriesKey = new ExpoServiceKey<ExpoRuntimeDirectories>('ExpoRuntimeDirectories');

export class ExpoAppDirectories extends ExpoService implements ExpoRuntimeDirectories {
  static readonly key = new ExpoServiceKey<ExpoAppDirectories>('ExpoAppDirectories');
  readonly identity = ExpoAppDirectories.key.bind(this);
  readonly interfaces = [ExpoRuntimeDirectoriesKey.bind(this)];

  directory(base: string): string {
    return base;
  }

  preferenceName(name: string): string {
    return name;
  }
}

export class ExpoScopedDirectories extends ExpoService implements ExpoRuntimeDirectories {
  static readonly key = new ExpoServiceKey<ExpoScopedDirectories>('ExpoScopedDirectories');
  readonly identity = ExpoScopedDirectories.key.bind(this);
  readonly interfaces = [ExpoRuntimeDirectoriesKey.bind(this)];

  private readonly name: string;

  readonly projectId: string;

  constructor(projectId: string) {
    super();
    if (projectId.length === 0) throw new Error('Expo project ID cannot be empty.');

    this.projectId = projectId;
    this.name = `scope-${encodeURIComponent(projectId)}`;
  }

  directory(base: string): string {
    const parent = `${base}/ExperienceData`;
    const path = `${parent}/${this.name}`;

    for (const directory of [parent, path]) {
      if (!fs.accessSync(directory)) fs.mkdirSync(directory);

      const stat = fs.lstatSync(directory);
      if (stat.isSymbolicLink() || !stat.isDirectory()) {
        throw new Error('Expo runtime directory must be a directory without symbolic links.');
      }
    }

    return path;
  }

  preferenceName(name: string): string {
    return `${this.name}#${name}`;
  }
}
