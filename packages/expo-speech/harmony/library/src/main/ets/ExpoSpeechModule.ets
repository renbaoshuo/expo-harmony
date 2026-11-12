/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { i18n } from '@kit.LocalizationKit';
import { SPEECH_OPTIONS, SpeechOptions } from './SpeechOptions';

const SPEAKING_STARTED = 'Exponent.speakingStarted';
const SPEAKING_BOUNDARY = 'Exponent.speakingWillSayNextString';
const SPEAKING_DONE = 'Exponent.speakingDone';
const SPEAKING_STOPPED = 'Exponent.speakingStopped';
const SPEAKING_ERROR = 'Exponent.speakingError';
const ERR_SPEECH_UNAVAILABLE = 'ERR_SPEECH_UNAVAILABLE';

const MAX_SPEECH_INPUT_LENGTH = 10000;
const OFFLINE_MODE = 1;
const PLAYBACK_COMPLETE = 1;
const INSTALLED_VOICE = 'INSTALLED';
const MIN_RATE_AND_PITCH = 0.5;
const MAX_RATE_AND_PITCH = 2;

interface Voice {
  identifier: string;
  name: string;
  language: string;
  quality: string;
}

class Utterance {
  readonly request: string = createRequestId();
  readonly id: string;
  readonly text: string;
  readonly options: SpeechOptions;
  started: boolean = false;

  constructor(id: string, text: string, options: SpeechOptions) {
    this.id = id;
    this.text = text;
    this.options = options;
  }
}

export class ExpoSpeechModule extends ExpoModule {
  private engine?: textToSpeech.TextToSpeechEngine;
  private voice?: string;
  private queue: Utterance[] = [];
  private current?: Utterance;
  private creatingEngine?: Promise<void>;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoSpeech')
      .constant('maxSpeechInputLength', MAX_SPEECH_INPUT_LENGTH)
      .events([SPEAKING_STARTED, SPEAKING_BOUNDARY, SPEAKING_DONE, SPEAKING_STOPPED, SPEAKING_ERROR])
      .asyncFunction(
        'speak',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          SPEECH_OPTIONS,
          async (id: string, text: string, options: SpeechOptions): Promise<void> => {
            this.assertActive();

            this.queue.push(new Utterance(id, text, options));
            this.startNext();
          },
        ),
      )
      .asyncFunction('getVoices', async (): Promise<Voice[]> => {
        let voices: textToSpeech.VoiceInfo[];
        try {
          voices = await this.getNativeVoices();
        } catch (error) {
          this.assertActive();

          // Match Android's empty list for unavailable TTS and keep catalog failures observable.
          if (error instanceof ExpoModuleError && error.code === ERR_SPEECH_UNAVAILABLE) return [];

          throw new ExpoModuleError('ERR_SPEECH_UNABLE_TO_GET_VOICES', `Unable to get voices: ${describeError(error)}`);
        }

        return voices.map(
          (voice: textToSpeech.VoiceInfo): Voice => ({
            identifier: voiceIdentifier(voice),
            name: voice.description || voiceIdentifier(voice),
            language: normalizeLanguage(voice.language),
            quality: 'Default',
          }),
        );
      })
      .asyncFunction('isSpeaking', async (): Promise<boolean> => {
        this.assertActive();

        return this.engine?.isBusy() ?? false;
      })
      .asyncFunction('stop', async (): Promise<void> => this.stop())
      .onPrepareForReload(async (): Promise<void> => {
        this.destroy();
        await this.creatingEngine;
      })
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private async getNativeVoices(): Promise<textToSpeech.VoiceInfo[]> {
    this.assertActive();
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      throw new ExpoModuleError(ERR_SPEECH_UNAVAILABLE, 'This device does not support Core Speech Kit text-to-speech.');
    }

    const voices = await textToSpeech.listVoices({
      requestId: createRequestId(),
      online: OFFLINE_MODE,
    });

    this.assertActive();

    return voices.filter((voice: textToSpeech.VoiceInfo): boolean => voice.status === undefined || voice.status === INSTALLED_VOICE);
  }

  private startNext(): void {
    if (this.destroyed || this.current !== undefined || this.creatingEngine !== undefined) return;

    const item = this.queue.shift();
    if (item === undefined) return;

    this.current = item;
    void Promise.resolve().then((): Promise<void> => this.prepare(item));
  }

  private async prepare(item: Utterance): Promise<void> {
    try {
      if (!this.isCurrent(item.request)) return;

      const textLength = item.text.trim().length;
      validateUtterance(item.options, textLength);

      const voices = await this.getNativeVoices();

      if (!this.isCurrent(item.request)) return;

      const voice = selectVoice(voices, item.options);
      if (textLength === 0) {
        this.started(item.request);
        this.finish(item.request, SPEAKING_DONE);

        return;
      }

      const identifier = voiceIdentifier(voice);

      if (this.voice !== identifier) {
        // Voice queries only read catalog data. Only engine creation needs to hold the queue after stop().
        this.creatingEngine = this.createEngine(item.request, voice, identifier).finally((): void => {
          this.creatingEngine = undefined;
          this.startNext();
        });
        await this.creatingEngine;
        if (!this.isCurrent(item.request)) return;
      }

      const options = item.options;
      const params: Record<string, Object> = {};
      params['speed'] = options.rate;
      params['pitch'] = options.pitch;
      params['volume'] = Math.min(1, Math.max(0, options.volume));
      // Core Speech Kit defaults to zh-CN for numerals and only accepts zh-CN or en-US here.
      if (normalizeLanguage(voice.language) === 'en-US') params['languageContext'] = 'en-US';

      this.engine!.speak(item.text, { requestId: item.request, extraParams: params });
    } catch (error) {
      // Upstream JS wraps this event's error string in Error, so retain our code in its message.
      this.finish(item.request, SPEAKING_ERROR, describeError(error));
    }
  }

  private async createEngine(request: string, voice: textToSpeech.VoiceInfo, identifier: string): Promise<void> {
    this.releaseEngine();

    const engine = await textToSpeech.createEngine({
      language: voice.language,
      person: voice.person,
      online: OFFLINE_MODE,
      extraParams: { style: voice.style },
    });

    this.engine = engine;
    if (!this.isCurrent(request)) {
      try {
        this.releaseEngine();
      } catch (error) {
        console.warn(`ExpoSpeech: failed to shut down the cancelled speech engine: ${describeError(error)}`);
      }
      return;
    }

    engine.setListener({
      onStart: (request: string, _response: textToSpeech.StartResponse): void => this.started(request),
      onComplete: (request: string, response: textToSpeech.CompleteResponse): void => {
        if (response.type === PLAYBACK_COMPLETE) this.finish(request, SPEAKING_DONE);
      },
      onStop: (request: string, _response: textToSpeech.StopResponse): void => this.finish(request, SPEAKING_STOPPED),
      onError: (request: string, code: number, message: string): void => {
        this.finish(request, SPEAKING_ERROR, `${message} (${code})`);
      },
    });
    this.voice = identifier;
  }

  private started(request: string): void {
    if (!this.isCurrent(request) || this.current!.started) return;

    this.current!.started = true;
    this.publish(SPEAKING_STARTED, this.current!.id);
  }

  private finish(request: string, event: string, error?: string): void {
    if (!this.isCurrent(request)) return;

    const item = this.current!;
    this.current = undefined;
    this.publish(event, item.id, error);
    this.startNext();
  }

  private stop(): void {
    this.assertActive();

    const cancelled = this.queue;
    this.queue = [];
    if (this.current !== undefined) cancelled.unshift(this.current);
    this.current = undefined;

    try {
      try {
        this.engine?.stop();
      } finally {
        // A pending native stop must not cancel speech submitted after this call.
        this.releaseEngine();
      }
    } catch (error) {
      const message = describeError(error);
      cancelled.forEach((item: Utterance): void => this.publish(SPEAKING_ERROR, item.id, message));

      throw new ExpoModuleError('ERR_SPEECH_STOP', `Unable to stop speech: ${message}`);
    }

    cancelled.forEach((item: Utterance): void => this.publish(SPEAKING_STOPPED, item.id));
  }

  private isCurrent(request: string): boolean {
    return !this.destroyed && this.context.isValid && this.current?.request === request;
  }

  private publish(event: string, id: string, error?: string): void {
    if (this.destroyed || !this.context.isValid) return;

    const payload: Record<string, ESObject> = error === undefined ? { 'id': id } : { 'id': id, 'error': error };
    this.sendEvent(event, payload);
  }

  private releaseEngine(): void {
    // Keep the handle if shutdown fails so a later cleanup can retry it.
    this.voice = undefined;
    this.engine?.shutdown();
    this.engine = undefined;
  }

  private destroy(): void {
    this.destroyed = true;
    this.queue = [];
    this.current = undefined;

    try {
      try {
        this.engine?.stop();
      } finally {
        this.releaseEngine();
      }
    } catch (error) {
      console.warn(`ExpoSpeech: failed to stop or shut down the speech engine: ${describeError(error)}`);
    }
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_SPEECH_DESTROYED', 'The Expo Speech runtime has already been destroyed.');
    }
  }
}

function describeError(error: ESObject): string {
  if (error instanceof ExpoModuleError) return `${error.code}: ${error.message}`;

  const native = error as BusinessError;
  if (typeof native?.code === 'number' && typeof native.message === 'string') {
    return `${native.message} (${native.code})`;
  }

  return String(error);
}

function createRequestId(): string {
  // Core Speech Kit accepts letters/digits, but RFC 4122 UUIDs also contain hyphens.
  return util.generateRandomUUID().replace(/-/g, '');
}

function normalizeLanguage(language: string): string {
  return parseLanguage(language)?.baseName ?? language.replace(/_/g, '-');
}

function parseLanguage(language: string): Intl.Locale | undefined {
  try {
    return new Intl.Locale(language.replace(/_/g, '-'));
  } catch {
    // Like SDK 57 Android, preserve non-standard engine locales instead of failing the whole voice list.
    return undefined;
  }
}

function voiceIdentifier(voice: textToSpeech.VoiceInfo): string {
  return JSON.stringify([normalizeLanguage(voice.language), voice.person, voice.style]);
}

function voiceForLanguage(voices: textToSpeech.VoiceInfo[], language: string): textToSpeech.VoiceInfo | undefined {
  const locale = parseLanguage(language);
  if (locale === undefined) return undefined;

  return (
    voices.find((voice: textToSpeech.VoiceInfo): boolean => normalizeLanguage(voice.language) === locale.baseName) ??
    voices.find((voice: textToSpeech.VoiceInfo): boolean => parseLanguage(voice.language)?.language === locale.language)
  );
}

function selectVoice(voices: textToSpeech.VoiceInfo[], options: SpeechOptions): textToSpeech.VoiceInfo {
  if (options.voice !== undefined) {
    const voice = voices.find((candidate: textToSpeech.VoiceInfo): boolean => voiceIdentifier(candidate) === options.voice);
    if (voice !== undefined) return voice;

    throw new ExpoModuleError('ERR_SPEECH_INVALID_VOICE', `Voice '${options.voice}' is not installed on this device.`);
  }

  if (voices.length === 0) throw new ExpoModuleError('ERR_SPEECH_NO_VOICES', 'No installed offline speech voices are available.');

  const requested = options.language === undefined ? undefined : voiceForLanguage(voices, options.language);

  return requested ?? voiceForLanguage(voices, i18n.System.getSystemLanguage()) ?? voices[0];
}

function validateUtterance(options: SpeechOptions, textLength: number): void {
  if (textLength > MAX_SPEECH_INPUT_LENGTH) {
    throw new ExpoModuleError('ERR_SPEECH_INPUT_IS_TOO_LONG', `Speech input text is too long! Limit of input length is: ${MAX_SPEECH_INPUT_LENGTH}`);
  }

  if (!Number.isFinite(options.volume)) throw new ExpoModuleError('ERR_SPEECH_INVALID_OPTIONS', 'volume must be finite.');
  if (
    !Number.isFinite(options.rate) ||
    options.rate < MIN_RATE_AND_PITCH ||
    options.rate > MAX_RATE_AND_PITCH ||
    !Number.isFinite(options.pitch) ||
    options.pitch < MIN_RATE_AND_PITCH ||
    options.pitch > MAX_RATE_AND_PITCH
  ) {
    throw new ExpoModuleError(
      'ERR_SPEECH_INVALID_OPTIONS',
      `rate and pitch must be between ${MIN_RATE_AND_PITCH} and ${MAX_RATE_AND_PITCH} on HarmonyOS.`,
    );
  }
}
