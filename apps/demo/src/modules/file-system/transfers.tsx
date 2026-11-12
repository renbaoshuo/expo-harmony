/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { DownloadTask, File, UploadTask, UploadType, type DownloadPauseState, type DownloadTaskOptions, type UploadOptions } from 'expo-file-system';
import * as Legacy from 'expo-file-system/legacy';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../../ui';
import { FileActions, localDirectory, localFile, Toggle } from './shared';

function parseFields(value: string) {
  const fields: unknown = JSON.parse(value || '{}');
  if (!fields || typeof fields !== 'object' || Array.isArray(fields) || Object.values(fields).some(field => typeof field !== 'string')) {
    throw new Error('请输入值均为字符串的 JSON 对象。');
  }
  return fields as Record<string, string>;
}

type ProgressListener = { remove(): void };

export function FileSystemTransfersDemo() {
  return (
    <>
      <DownloadDemo />
      <UploadDemo />
      <LegacyTransfers />
    </>
  );
}

function DownloadDemo() {
  const [url, setUrl] = useState('https://example.com/');
  const [path, setPath] = useState('download.html');
  const [headers, setHeaders] = useState('{}');
  const [directoryTarget, setDirectoryTarget] = useState(false);
  const [idempotent, setIdempotent] = useState(false);
  const [background, setBackground] = useState(false);
  const [trackProgress, setTrackProgress] = useState(true);
  const [progress, setProgress] = useState<object>();
  const [saved, setSaved] = useState<DownloadPauseState>();
  const [state, setState] = useState<DownloadTask['state']>();
  const task = useRef<DownloadTask | null>(null);
  const inFlight = useRef<DownloadTask | null>(null);
  const subscription = useRef<ProgressListener | null>(null);
  const taskController = useRef<AbortController | null>(null);
  const directController = useRef<AbortController | null>(null);
  const result = useAsyncResult();

  useEffect(() => () => {
    directController.current?.abort();
    subscription.current?.remove();
    const current = task.current;
    task.current = null;
    if (current && inFlight.current === current) current.cancel();
    else current?.release();
  }, []);

  const target = () => directoryTarget ? localDirectory(path) : localFile(path);
  const options = (signal: AbortSignal): DownloadTaskOptions => ({
    signal,
    headers: parseFields(headers),
    sessionType: background ? 'background' : 'foreground',
    onProgress: trackProgress ? setProgress : undefined,
  });
  const register = (create: (signal: AbortSignal) => DownloadTask) => {
    if (task.current?.state === 'active') throw new Error('请先停止当前下载。');
    const abort = new AbortController();
    const next = create(abort.signal);
    taskController.current = abort;
    subscription.current?.remove();
    subscription.current = null;
    task.current?.release();
    task.current = next;
    setState(next.state);
    return next.state;
  };
  const download = (resume: boolean) => result.run(async () => {
    const current = task.current;
    if (!current) return '';
    inFlight.current = current;
    setProgress(undefined);
    try {
      const pending = resume ? current.resumeAsync() : current.downloadAsync();
      setState(current.state);
      return json((await pending)?.uri ?? null);
    } finally {
      inFlight.current = null;
      if (task.current === current) setState(current.state);
      else current.release();
    }
  });
  const direct = () => result.run(async () => {
    const controller = new AbortController();
    directController.current = controller;
    setProgress(undefined);
    try {
      return json((await File.downloadFileAsync(url, target(), {
        headers: parseFields(headers),
        idempotent,
        onProgress: trackProgress ? setProgress : undefined,
        signal: controller.signal,
      })).uri);
    } finally {
      directController.current = null;
    }
  });

  return (
    <Panel title="下载文件">
      <Field label="下载 URL" onChangeText={setUrl} value={url} />
      <Field label="目标相对路径" onChangeText={setPath} value={path} />
      <Field label="请求头 JSON" multiline onChangeText={setHeaders} value={headers} />
      <ActionRow>
        <Toggle label="目标为目录" value={directoryTarget} onChange={setDirectoryTarget} />
        <Toggle label="idempotent" value={idempotent} onChange={setIdempotent} />
        <Toggle label="onProgress" value={trackProgress} onChange={setTrackProgress} />
        {Platform.OS === 'ios' ? <Toggle label="后台会话" value={background} onChange={setBackground} /> : null}
      </ActionRow>
      <ActionRow>
        <ActionButton label="downloadFileAsync()" disabled={result.state.phase === 'running'} onPress={() => void direct()} />
        <ActionButton label="signal.abort()" disabled={!directController.current} onPress={() => directController.current?.abort()} tone="danger" />
      </ActionRow>
      <FileActions actions={[
        ['准备目标目录', () => localDirectory(path).create({ idempotent: true, intermediates: true }), !directoryTarget],
        ['createDownloadTask()', () => register(signal => File.createDownloadTask(url, target(), options(signal))), result.state.phase === 'running'],
        ['new DownloadTask()', () => register(signal => new DownloadTask(url, target(), options(signal))), result.state.phase === 'running'],
        ['pause()', () => task.current?.pause(), state !== 'active'],
        ['pauseAsync()', () => task.current?.pauseAsync(), state !== 'active'],
        ['cancel()', () => {
          task.current?.cancel();
          setState(task.current?.state);
        }, !task.current],
        ['中止任务信号', () => taskController.current?.abort(), state !== 'active'],
        ['savable()', () => {
          const value = task.current?.savable();
          setSaved(value);
          return value;
        }, state !== 'paused'],
        ['fromSavable()', () => saved && register(signal => DownloadTask.fromSavable(saved, options(signal))), !saved || result.state.phase === 'running'],
        ['addListener()', () => {
          subscription.current?.remove();
          subscription.current = task.current?.addListener('progress', setProgress) ?? null;
        }, !task.current],
        ['remove()', () => {
          subscription.current?.remove();
          subscription.current = null;
        }, !task.current],
        ['release()', () => {
          subscription.current?.remove();
          subscription.current = null;
          task.current?.release();
          task.current = null;
          setState(undefined);
        }, !task.current || result.state.phase === 'running'],
      ]}
      />
      <ActionRow>
        <ActionButton label="downloadAsync()" disabled={state !== 'idle' || result.state.phase === 'running'} onPress={() => void download(false)} />
        <ActionButton label="resumeAsync()" disabled={state !== 'paused' || result.state.phase === 'running'} onPress={() => void download(true)} />
      </ActionRow>
      {state ? <DataRow label="state" value={state} /> : null}
      {progress ? <DataRow label="进度" value={json(progress)} /> : null}
      <ResultPanel state={result.state} />
    </Panel>
  );
}

const httpMethods = ['POST', 'PUT', 'PATCH'] as const;

function UploadDemo() {
  const [url, setUrl] = useState('https://httpbin.org/anything');
  const [path, setPath] = useState('upload-sample.txt');
  const [headers, setHeaders] = useState('{}');
  const [parameters, setParameters] = useState('{}');
  const [method, setMethod] = useState<typeof httpMethods[number]>('POST');
  const [multipart, setMultipart] = useState(false);
  const [fieldName, setFieldName] = useState('file');
  const [mimeType, setMimeType] = useState('text/plain');
  const [background, setBackground] = useState(false);
  const [trackProgress, setTrackProgress] = useState(true);
  const [progress, setProgress] = useState<object>();
  const [state, setState] = useState<UploadTask['state']>();
  const task = useRef<UploadTask | null>(null);
  const inFlight = useRef<UploadTask | null>(null);
  const subscription = useRef<ProgressListener | null>(null);
  const taskController = useRef<AbortController | null>(null);
  const controller = useRef<AbortController | null>(null);
  const result = useAsyncResult();

  useEffect(() => () => {
    controller.current?.abort();
    subscription.current?.remove();
    const current = task.current;
    task.current = null;
    if (current && inFlight.current === current) current.cancel();
    else current?.release();
  }, []);

  const options = (signal: AbortSignal): UploadOptions => ({
    signal,
    httpMethod: method,
    uploadType: multipart ? UploadType.MULTIPART : UploadType.BINARY_CONTENT,
    headers: parseFields(headers),
    ...(multipart ? { fieldName, mimeType, parameters: parseFields(parameters) } : {}),
    sessionType: background ? 'background' : 'foreground',
    onProgress: trackProgress ? setProgress : undefined,
  });
  const register = (directConstructor: boolean) => {
    if (task.current?.state === 'active') throw new Error('请先停止当前上传。');
    const file = localFile(path);
    const abort = new AbortController();
    const config = options(abort.signal);
    const next = directConstructor ? new UploadTask(file, url, config) : file.createUploadTask(url, config);
    taskController.current = abort;
    subscription.current?.remove();
    subscription.current = null;
    task.current?.release();
    task.current = next;
    setState(next.state);
  };
  const upload = (direct: boolean) => result.run(async () => {
    setProgress(undefined);
    if (!direct && task.current) {
      const current = task.current;
      inFlight.current = current;
      try {
        const pending = current.uploadAsync();
        setState(current.state);
        return json(await pending);
      } finally {
        inFlight.current = null;
        if (task.current === current) setState(current.state);
        else current.release();
      }
    }
    const abort = new AbortController();
    controller.current = abort;
    try {
      return json(await localFile(path).upload(url, options(abort.signal)));
    } finally {
      controller.current = null;
    }
  });

  return (
    <Panel title="上传文件">
      <Field label="上传 URL" onChangeText={setUrl} value={url} />
      <Field label="文件相对路径" onChangeText={setPath} value={path} />
      <Field label="请求头 JSON" multiline onChangeText={setHeaders} value={headers} />
      <ActionRow>
        {httpMethods.map(value => (
          <Toggle key={value} label={value} value={method === value} onChange={() => setMethod(value)} />
        ))}
        <Toggle label="multipart" value={multipart} onChange={setMultipart} />
        <Toggle label="onProgress" value={trackProgress} onChange={setTrackProgress} />
        {Platform.OS === 'ios' ? <Toggle label="后台会话" value={background} onChange={setBackground} /> : null}
      </ActionRow>
      {multipart
        ? (
            <>
              <Field label="文件表单字段" onChangeText={setFieldName} value={fieldName} />
              <Field label="文件 MIME 类型" onChangeText={setMimeType} value={mimeType} />
              <Field label="附加表单字段 JSON" multiline onChangeText={setParameters} value={parameters} />
            </>
          )
        : null}
      <FileActions actions={[
        ['准备示例文件', () => {
          const file = localFile(path);
          file.create({ intermediates: true, overwrite: true });
          file.write('你好，文件上传');
          return file.uri;
        }, result.state.phase === 'running'],
        ['createUploadTask()', () => register(false), result.state.phase === 'running'],
        ['new UploadTask()', () => register(true), result.state.phase === 'running'],
        ['addListener()', () => {
          subscription.current?.remove();
          subscription.current = task.current?.addListener('progress', setProgress) ?? null;
        }, !task.current],
        ['remove()', () => {
          subscription.current?.remove();
          subscription.current = null;
        }, !task.current],
        ['cancel()', () => {
          task.current?.cancel();
          setState(task.current?.state);
        }, !task.current],
        ['中止任务信号', () => taskController.current?.abort(), state !== 'active'],
        ['release()', () => {
          subscription.current?.remove();
          subscription.current = null;
          task.current?.release();
          task.current = null;
          setState(undefined);
        }, !task.current || result.state.phase === 'running'],
      ]}
      />
      <ActionRow>
        <ActionButton label="upload()" disabled={result.state.phase === 'running'} onPress={() => void upload(true)} />
        <ActionButton label="uploadAsync()" disabled={state !== 'idle' || result.state.phase === 'running'} onPress={() => void upload(false)} />
        <ActionButton label="signal.abort()" disabled={!controller.current} onPress={() => controller.current?.abort()} tone="danger" />
      </ActionRow>
      {state ? <DataRow label="state" value={state} /> : null}
      {progress ? <DataRow label="进度" value={json(progress)} /> : null}
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function LegacyTransfers() {
  const [url, setUrl] = useState('https://example.com/');
  const [path, setPath] = useState('legacy-download.html');
  const [headers, setHeaders] = useState('{}');
  const [md5, setMD5] = useState(false);
  const [cache, setCache] = useState(true);
  const [background, setBackground] = useState(false);
  const [multipart, setMultipart] = useState(false);
  const [method, setMethod] = useState<typeof httpMethods[number]>('POST');
  const [field, setField] = useState('file');
  const [mime, setMime] = useState('text/plain');
  const [parameters, setParameters] = useState('{}');
  const [progress, setProgress] = useState<object>();
  const [resumeData, setResumeData] = useState<string>();
  const [hasDownload, setHasDownload] = useState(false);
  const [hasUpload, setHasUpload] = useState(false);
  const [downloadActive, setDownloadActive] = useState(false);
  const download = useRef<Legacy.DownloadResumable | null>(null);
  const upload = useRef<Legacy.UploadTask | null>(null);
  const result = useAsyncResult();
  const busy = result.state.phase === 'running';
  const sessionType = Platform.OS === 'ios'
    ? background ? Legacy.FileSystemSessionType.BACKGROUND : Legacy.FileSystemSessionType.FOREGROUND
    : undefined;
  const downloadOptions = (): Legacy.DownloadOptions => ({
    md5, headers: parseFields(headers), sessionType, cache: Platform.OS === 'ios' ? cache : undefined,
  });
  const uploadOptions = (): Legacy.FileSystemUploadOptions => ({
    headers: parseFields(headers), httpMethod: method, sessionType,
    ...(multipart
      ? {
          uploadType: Legacy.FileSystemUploadType.MULTIPART,
          fieldName: field,
          mimeType: mime,
          parameters: parseFields(parameters),
        }
      : { uploadType: Legacy.FileSystemUploadType.BINARY_CONTENT }),
  });
  const uri = () => localFile(path).uri;
  const run = (operation: () => Promise<unknown> | undefined) => (
    result.run(async () => json(await operation() ?? null))
  );
  const runDownload = (resume: boolean) => run(async () => {
    const current = download.current;
    if (!current) return null;
    setDownloadActive(true);
    try {
      return await (resume ? current.resumeAsync() : current.downloadAsync());
    } finally {
      setDownloadActive(false);
    }
  });

  useEffect(() => () => {
    void download.current?.cancelAsync().catch(() => undefined);
    void upload.current?.cancelAsync().catch(() => undefined);
  }, []);

  return (
    <Panel title="旧版传输 API">
      <Field label="传输 URL" onChangeText={setUrl} value={url} />
      <Field label="文件相对路径" onChangeText={setPath} value={path} />
      <Field label="请求头 JSON" onChangeText={setHeaders} value={headers} />
      <ActionRow>
        <Toggle label="md5" value={md5} onChange={setMD5} />
        {Platform.OS === 'ios' ? <Toggle label="cache" value={cache} onChange={setCache} /> : null}
        {Platform.OS === 'ios' ? <Toggle label="后台会话" value={background} onChange={setBackground} /> : null}
        <Toggle label="multipart" value={multipart} onChange={setMultipart} />
        {httpMethods.map(value => (
          <Toggle key={value} label={value} value={method === value} onChange={() => setMethod(value)} />
        ))}
      </ActionRow>
      {multipart
        ? (
            <>
              <Field label="文件表单字段" onChangeText={setField} value={field} />
              <Field label="文件 MIME 类型" onChangeText={setMime} value={mime} />
              <Field label="附加表单字段 JSON" onChangeText={setParameters} value={parameters} />
            </>
          )
        : null}
      <FileActions actions={[
        ['createDownloadResumable()', () => {
          download.current = Legacy.createDownloadResumable(url, uri(), downloadOptions(), setProgress, resumeData);
          setHasDownload(true);
        }, busy],
        ['pauseAsync()', async () => {
          const value = await download.current?.pauseAsync();
          setResumeData(value?.resumeData);
          return value;
        }, !downloadActive],
        ['savable()', () => download.current?.savable(), !hasDownload],
        ['取消下载', () => download.current?.cancelAsync(), !hasDownload],
        ['createUploadTask()', () => {
          upload.current = Legacy.createUploadTask(url, uri(), uploadOptions(), setProgress);
          setHasUpload(true);
        }, busy],
        ['取消上传', () => upload.current?.cancelAsync(), !hasUpload],
      ]}
      />
      <ActionRow>
        <ActionButton label="直接下载" disabled={busy} onPress={() => void run(() => Legacy.downloadAsync(url, uri(), downloadOptions()))} />
        <ActionButton label="任务下载" disabled={busy || !hasDownload} onPress={() => void runDownload(false)} />
        <ActionButton label="resumeAsync()" disabled={busy || !hasDownload} onPress={() => void runDownload(true)} />
        <ActionButton label="直接上传" disabled={busy} onPress={() => void run(() => Legacy.uploadAsync(url, uri(), uploadOptions()))} />
        <ActionButton label="任务上传" disabled={busy || !hasUpload} onPress={() => void run(() => upload.current?.uploadAsync())} />
      </ActionRow>
      {progress ? <DataRow label="进度" value={json(progress)} /> : null}
      <ResultPanel state={result.state} />
    </Panel>
  );
}
