export const APP_STARTUP_CATEGORY: string = 'appStartup';
export const FRAME_RATE_CATEGORY: string = 'frameRate';
export const MEMORY_CATEGORY: string = 'memory';

export const BUNDLE_LOAD_METRIC: string = 'bundleLoadTime';
export const FIRST_RENDER_METRIC: string = 'timeToFirstRender';
export const INTERACTIVE_METRIC: string = 'timeToInteractive';
export const PHYSICAL_MEMORY_METRIC: string = 'physical';
export const AVAILABLE_MEMORY_METRIC: string = 'available';

export class FrameMetricsRecord {
  sessionDurationMs: number = 0;
  renderedFrames: number = 0;
  expectedFrames: number = 0;
  droppedFrames: number = 0;
  frozenFrames: number = 0;
  slowFrames: number = 0;
  freezeTimeMs: number = 0;
}

export class FrameRateMetrics {
  renderedFrames: number;
  expectedFrames: number;
  droppedFrames: number;
  frozenFrames: number;
  slowFrames: number;
  freezeTime: number;
  sessionDuration: number;

  constructor(record: FrameMetricsRecord) {
    this.renderedFrames = record.renderedFrames;
    this.expectedFrames = record.expectedFrames;
    this.droppedFrames = record.droppedFrames;
    this.frozenFrames = record.frozenFrames;
    this.slowFrames = record.slowFrames;
    this.freezeTime = record.freezeTimeMs / 1000;
    this.sessionDuration = record.sessionDurationMs / 1000;
  }
}

export class MemoryUsageSnapshot {
  physical: number;
  available: number;

  constructor(physical: number, available: number) {
    this.physical = physical;
    this.available = available;
  }
}

export class Metric {
  metricId: string;
  sessionId: string;
  timestamp: string;
  category: string;
  name: string;
  value: number;
  routeName?: string;
  updateId?: string;
  params?: Record<string, ESObject>;

  constructor(
    metricId: string,
    sessionId: string,
    timestamp: string,
    category: string,
    name: string,
    value: number,
    routeName?: string,
    params?: Record<string, ESObject>
  ) {
    this.metricId = metricId;
    this.sessionId = sessionId;
    this.timestamp = timestamp;
    this.category = category;
    this.name = name;
    this.value = value;
    this.routeName = routeName;
    this.params = params;
  }
}

export class AppMetadata {
  appName?: string;
  appIdentifier?: string;
  appVersion?: string;
  appBuildNumber?: string;
  appUpdateId?: string;
  appEasBuildId?: string;
  deviceOs?: string;
  deviceOsVersion?: string;
  deviceModel?: string;
  deviceName?: string;
  expoSdkVersion?: string;
  reactNativeVersion?: string;
  clientVersion?: string;
  languageTag?: string;
}

export class Session {
  id: string;
  startTimestamp: string;
  isActive: boolean;
  environment?: string;
  appName?: string;
  appIdentifier?: string;
  appVersion?: string;
  appBuildNumber?: string;
  appUpdateId?: string;
  appEasBuildId?: string;
  deviceOs?: string;
  deviceOsVersion?: string;
  deviceModel?: string;
  deviceName?: string;
  expoSdkVersion?: string;
  reactNativeVersion?: string;
  clientVersion?: string;
  languageTag?: string;

  constructor(id: string, startTimestamp: string, environment?: string, metadata?: AppMetadata) {
    this.id = id;
    this.startTimestamp = startTimestamp;
    this.isActive = true;
    this.environment = environment;
    this.appName = metadata?.appName;
    this.appIdentifier = metadata?.appIdentifier;
    this.appVersion = metadata?.appVersion;
    this.appBuildNumber = metadata?.appBuildNumber;
    this.appUpdateId = metadata?.appUpdateId;
    this.appEasBuildId = metadata?.appEasBuildId;
    this.deviceOs = metadata?.deviceOs;
    this.deviceOsVersion = metadata?.deviceOsVersion;
    this.deviceModel = metadata?.deviceModel;
    this.deviceName = metadata?.deviceName;
    this.expoSdkVersion = metadata?.expoSdkVersion;
    this.reactNativeVersion = metadata?.reactNativeVersion;
    this.clientVersion = metadata?.clientVersion;
    this.languageTag = metadata?.languageTag;
  }
}

export class SessionWithMetrics {
  session: Session;
  metrics: Metric[];

  constructor(session: Session, metrics: Metric[] = []) {
    this.session = session;
    this.metrics = metrics;
  }
}
