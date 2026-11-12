/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { File, Paths } from 'expo-file-system';
import type * as Modern from 'expo-media-library';
import * as Legacy from 'expo-media-library/legacy';
import { useEffect, useRef, useState } from 'react';
import { Image, Platform, StyleSheet, Switch } from 'react-native';

import picture from '../../assets/app-icon.png';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

type ModernApi = typeof Modern;
type MediaApi = typeof Legacy | ModernApi;
type AssetIdProps = { assetId: string; setAssetId: (id: string) => void };
type AlbumIdProps = { albumId: string; setAlbumId: (id: string) => void };

function listIds(value: string) {
  return value.split(/[,\n]+/).map(id => id.trim()).filter(Boolean);
}

function nonnegativeInteger(value: string, name: string) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) throw new Error(`${name}须为非负整数`);
  return number;
}

function MediaPermissionHook({ api, options, action }: {
  api: MediaApi;
  options: Parameters<MediaApi['usePermissions']>[0];
  action: ReturnType<typeof useAsyncResult>;
}) {
  const [permission, request, get] = api.usePermissions(options);
  const busy = action.state.phase === 'running';

  return (
    <>
      <DataRow label="权限状态" value={permission?.status ?? '加载中'} />
      <ActionRow>
        <ActionButton label="读取图库权限" disabled={busy} onPress={() => void action.run(async () => json(await get()))} testID="media-library-permissions" tone="secondary" />
        <ActionButton label="申请图库权限" disabled={busy} onPress={() => void action.run(async () => json(await request()))} testID="media-library-request" />
      </ActionRow>
    </>
  );
}

function MediaPermissionsCard({ api }: { api: MediaApi }) {
  const [writeOnly, setWriteOnly] = useState(false);
  const [types, setTypes] = useState<Legacy.GranularPermission[]>(['photo', 'video']);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const hasPermissionPicker = Platform.OS === 'ios' || Platform.OS === 'android';
  const options = { writeOnly, granularPermissions: Platform.OS === 'android' ? types : undefined };

  return (
    <Panel title="图库权限">
      <DataRow label="仅写入" value={<Switch disabled={busy} value={writeOnly} onValueChange={setWriteOnly} accessibilityLabel="仅写入" />} />
      {Platform.OS === 'android'
        ? (
            <ActionRow>
              {(['photo', 'video', 'audio'] as const).map(type => (
                <ActionButton key={type} disabled={busy} label={type} tone={types.includes(type) ? 'primary' : 'secondary'} onPress={() => setTypes(current => current.includes(type) ? current.filter(value => value !== type) : [...current, type])} />
              ))}
            </ActionRow>
          )
        : null}
      <MediaPermissionHook key={json(options)} api={api} options={options} action={action} />
      <ActionRow>
        {!('Asset' in api) ? <ActionButton label="检查图库可用性" disabled={busy} onPress={() => void action.run(async () => json(await api.isAvailableAsync()))} tone="secondary" /> : null}
        {hasPermissionPicker
          ? <ActionButton
              label="打开授权选择器"
              disabled={busy}
              onPress={() => void action.run(async () => {
                const picker = 'Asset' in api ? api.presentPermissionsPicker : api.presentPermissionsPickerAsync;
                const mediaTypes = types.filter(type => type !== 'audio');
                await picker(mediaTypes.length ? mediaTypes : undefined);
                return '授权选择器已关闭';
              })}
              tone="secondary"
            />
          : null}
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function MediaEventsCard({ api }: { api: MediaApi }) {
  const [event, setEvent] = useState<unknown>();
  const [listening, setListening] = useState(false);
  const subscription = useRef<ReturnType<typeof Legacy.addListener> | null>(null);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  useEffect(() => () => subscription.current?.remove(), []);

  const stop = (mode: 'current' | 'all' | 'legacy') => action.run(() => {
    if (mode === 'all') api.removeAllListeners();
    else if (mode === 'legacy' && !('Asset' in api) && subscription.current) api.removeSubscription(subscription.current);
    else subscription.current?.remove();
    subscription.current = null;
    setListening(false);
    return '已停止监听图库变更';
  });

  return (
    <Panel title="图库变更">
      <ActionRow>
        <ActionButton
          label="监听图库变更"
          disabled={busy || listening}
          onPress={() => void action.run(() => {
            subscription.current = api.addListener(setEvent);
            setEvent(undefined);
            setListening(true);
            return '已开始监听图库变更';
          })}
          testID="media-library-observe"
        />
        <ActionButton label="移除当前监听" disabled={busy || !listening} onPress={() => void stop('current')} tone="secondary" />
        <ActionButton label="移除全部监听" disabled={busy || !listening} onPress={() => void stop('all')} tone="secondary" />
        {!('Asset' in api) ? <ActionButton label="用 removeSubscription 移除监听" disabled={busy || !listening} onPress={() => void stop('legacy')} tone="secondary" /> : null}
      </ActionRow>
      {event ? <DataRow label="最近一次变更" value={json(event)} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function MediaImportCard({ api, albumId, setAlbumId, setAssetId }: { api: MediaApi } & AssetIdProps & AlbumIdProps) {
  const [uri, setUri] = useState('');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  const withFile = async <T,>(operation: (uri: string) => Promise<T>): Promise<T> => {
    if (uri.trim()) return operation(uri.trim());
    const asset = await Asset.fromModule(picture).downloadAsync();
    if (!asset.localUri) throw new Error('无法下载内置图片');
    const file = new File(Paths.cache, `media-library-${Date.now()}.png`);
    try {
      await new File(asset.localUri).copy(file);
      return await operation(file.uri);
    } finally {
      if (file.exists) file.delete();
    }
  };

  return (
    <Panel title="导入媒体">
      <Field label="本地文件 URI" value={uri} onChangeText={setUri} placeholder="内置图片" />
      <Field label="目标相册 ID" value={albumId} onChangeText={setAlbumId} />
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="导入资源"
          onPress={() => void action.run(async () => {
            const result = await withFile<{ id: string }>(file => 'Asset' in api
              ? api.Asset.create(file, albumId ? new api.Album(albumId) : undefined)
              : api.createAssetAsync(file, albumId || undefined));
            setAssetId(result.id);
            return json({ id: result.id });
          })}
          testID={!('Asset' in api) ? 'media-library-create' : 'media-library-next-create'}
        />
        {!('Asset' in api)
          ? <ActionButton
              disabled={busy}
              label="保存文件到图库"
              onPress={() => void action.run(async () => {
                await withFile(file => api.saveToLibraryAsync(file));
                return '文件已保存到图库';
              })}
              testID="media-library-save"
              tone="secondary"
            />
          : null}
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function LegacyQueryCard({ setAssetId, albumId, setAlbumId }: Pick<AssetIdProps, 'setAssetId'> & AlbumIdProps) {
  const [first, setFirst] = useState('5');
  const [after, setAfter] = useState('');
  const [mediaType, setMediaType] = useState<Legacy.MediaTypeValue[]>(['photo', 'video']);
  const [subtypes, setSubtypes] = useState('');
  const [sortBy, setSortBy] = useState('[["creationTime", false]]');
  const [createdAfter, setCreatedAfter] = useState('');
  const [createdBefore, setCreatedBefore] = useState('');
  const [fullInfo, setFullInfo] = useState(false);
  const [page, setPage] = useState<Legacy.PagedInfo<Legacy.Asset>>();
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  const query = () => action.run(async () => {
    const result = await Legacy.getAssetsAsync({
      first: first.trim() ? nonnegativeInteger(first, '每页数量') : undefined,
      after: after || undefined,
      album: albumId || undefined,
      mediaType: mediaType.length ? mediaType : undefined,
      mediaSubtypes: Platform.OS === 'ios' && subtypes.trim()
        ? JSON.parse(subtypes) as Legacy.AssetsOptions['mediaSubtypes']
        : undefined,
      sortBy: sortBy.trim() ? JSON.parse(sortBy) as Legacy.AssetsOptions['sortBy'] : undefined,
      createdAfter: createdAfter.trim() ? nonnegativeInteger(createdAfter, '创建时间起点') : undefined,
      createdBefore: createdBefore.trim() ? nonnegativeInteger(createdBefore, '创建时间终点') : undefined,
      resolveWithFullInfo: fullInfo,
    });
    setPage(result);
    return json({ totalCount: result.totalCount, endCursor: result.endCursor, hasNextPage: result.hasNextPage });
  });

  return (
    <Panel title="资源分页">
      <Field label="每页数量" value={first} onChangeText={setFirst} keyboardType="number-pad" />
      <Field label="分页游标" value={after} onChangeText={setAfter} />
      <Field label="相册 ID" value={albumId} onChangeText={setAlbumId} />
      <ActionRow>
        {(['photo', 'video', 'audio', 'unknown'] as const).map(type => (
          <ActionButton
            key={type}
            label={type}
            tone={mediaType.includes(type) ? 'primary' : 'secondary'}
            onPress={() => setMediaType(current => current.includes(type)
              ? current.filter(value => value !== type)
              : [...current, type])}
          />
        ))}
      </ActionRow>
      {Platform.OS === 'ios' ? <Field label="媒体子类型（JSON）" value={subtypes} onChangeText={setSubtypes} placeholder='["livePhoto"]' /> : null}
      <Field label="排序（JSON）" value={sortBy} onChangeText={setSortBy} />
      <Field label="创建时间起点（Unix 毫秒）" value={createdAfter} onChangeText={setCreatedAfter} keyboardType="number-pad" />
      <Field label="创建时间终点（Unix 毫秒）" value={createdBefore} onChangeText={setCreatedBefore} keyboardType="number-pad" />
      <DataRow label="读取完整图片信息" value={<Switch value={fullInfo} onValueChange={setFullInfo} accessibilityLabel="读取完整图片信息" />} />
      <ActionRow>
        <ActionButton disabled={busy} label="查询资源" onPress={() => void query()} testID="media-library-first" />
        <ActionButton disabled={busy || !page?.hasNextPage || !page.endCursor} label="填入下一页游标" onPress={() => setAfter(page?.endCursor ?? '')} testID="media-library-next" tone="secondary" />
      </ActionRow>
      {page?.assets.map(asset => (
        <ActionButton key={asset.id} label={asset.filename} onPress={() => setAssetId(asset.id)} tone="secondary" />
      ))}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function LegacyAssetCard({ assetId, setAssetId }: AssetIdProps) {
  const [download, setDownload] = useState(true);
  const [favorite, setFavorite] = useState(true);
  const [asset, setAsset] = useState<Legacy.AssetInfo>();
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="资源详情与删除">
      <Field label="资源 ID" value={assetId} onChangeText={setAssetId} />
      {Platform.OS === 'ios' ? <DataRow label="允许下载云端资源" value={<Switch value={download} onValueChange={setDownload} accessibilityLabel="允许下载云端资源" />} /> : null}
      {Platform.OS === 'ios' ? <DataRow label="收藏" value={<Switch value={favorite} onValueChange={setFavorite} accessibilityLabel="收藏" />} /> : null}
      <ActionRow>
        <ActionButton
          disabled={busy || !assetId}
          label="读取资源详情"
          onPress={() => void action.run(async () => {
            const info = await Legacy.getAssetInfoAsync(assetId, Platform.OS === 'ios' ? { shouldDownloadFromNetwork: download } : undefined);
            setAsset(info ?? undefined);
            return json(info);
          })}
          testID="media-library-info"
        />
        {Platform.OS === 'android' ? <ActionButton disabled={busy || !assetId} label="读取资源内容 URI" onPress={() => void action.run(() => Legacy.getAssetContentUriAsync(assetId))} tone="secondary" /> : null}
        {Platform.OS === 'ios' ? <ActionButton disabled={busy || !assetId} label="设置收藏状态" onPress={() => void action.run(async () => json(await Legacy.setAssetFavoriteAsync(assetId, favorite)))} tone="secondary" /> : null}
        <ActionButton
          disabled={busy || !assetId}
          label="删除资源"
          onPress={() => void action.run(async () => {
            const result = await Legacy.deleteAssetsAsync(assetId);
            if (result) setAssetId('');
            return json(result);
          })}
          testID="media-library-cleanup"
          tone="danger"
        />
      </ActionRow>
      {asset && asset.id === assetId && asset.mediaType === 'photo' ? <Image accessibilityLabel="图片预览" resizeMode="contain" source={{ uri: asset.uri }} style={styles.preview} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function LegacyAlbumCard({ assetId, albumId, setAlbumId }: { assetId: string } & AlbumIdProps) {
  const [title, setTitle] = useState('相机');
  const [albums, setAlbums] = useState<Legacy.Album[]>([]);
  const [smart, setSmart] = useState(false);
  const [copy, setCopy] = useState(true);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="相册">
      <Field label="相册名称" value={title} onChangeText={setTitle} testID="media-library-title" />
      <DataRow label="包含系统相册" value={<Switch value={smart} onValueChange={setSmart} accessibilityLabel="包含系统相册" />} />
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="列出相册"
          onPress={() => void action.run(async () => {
            const result = await Legacy.getAlbumsAsync({ includeSmartAlbums: smart });
            setAlbums(result);
            return json(result);
          })}
          testID="media-library-albums"
        />
        <ActionButton
          disabled={busy || !title}
          label="按名称查询相册"
          onPress={() => void action.run(async () => {
            const result = await Legacy.getAlbumAsync(title);
            if (result) setAlbumId(result.id);
            return json(result);
          })}
          testID="media-library-find-album"
          tone="secondary"
        />
      </ActionRow>
      {albums.map(album => <ActionButton key={album.id} label={album.title} tone={album.id === albumId ? 'primary' : 'secondary'} onPress={() => setAlbumId(album.id)} />)}
      <Field label="相册 ID" value={albumId} onChangeText={setAlbumId} />
      <DataRow label="资源 ID" value={assetId || '未选中'} />
      {Platform.OS === 'android' ? <DataRow label="复制资源" value={<Switch value={copy} onValueChange={setCopy} accessibilityLabel="复制资源" />} /> : null}
      <ActionRow>
        <ActionButton disabled={busy || !albumId || !assetId} label="加入相册" onPress={() => void action.run(async () => json(await Legacy.addAssetsToAlbumAsync(assetId, albumId, Platform.OS === 'android' ? copy : undefined)))} testID="media-library-add" tone="secondary" />
        <ActionButton disabled={busy || !albumId || !assetId} label="移出相册" onPress={() => void action.run(async () => json(await Legacy.removeAssetsFromAlbumAsync(assetId, albumId)))} testID="media-library-remove" tone="secondary" />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

const FILTERS = ['eq', 'within', 'gt', 'gte', 'lt', 'lte'] as const;
type Filter = (typeof FILTERS)[number];

function QueryCard({ api, setAssetId, albumId, setAlbumId }: { api: ModernApi } & Pick<AssetIdProps, 'setAssetId'> & AlbumIdProps) {
  const [field, setField] = useState<Modern.AssetField>(api.AssetField.MEDIA_TYPE);
  const [filter, setFilter] = useState<Filter | null>('eq');
  const [value, setValue] = useState('"image"');
  const [sort, setSort] = useState('');
  const [ascending, setAscending] = useState(true);
  const [limit, setLimit] = useState('5');
  const [offset, setOffset] = useState('');
  const [assets, setAssets] = useState<{ id: string }[]>([]);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const mediaField = api.AssetField.MEDIA_TYPE;
  const favoriteField = api.AssetField.IS_FAVORITE;
  const numericFilter = filter !== null && filter !== 'eq' && filter !== 'within';
  const fields = Object.values(api.AssetField).filter(
    key => !numericFilter || (key !== mediaField && key !== favoriteField)
  );

  const selectFilter = (operator: Filter | null) => {
    setFilter(operator);
    if (!operator) return;
    const numeric = operator !== 'eq' && operator !== 'within';
    const nextField = numeric && (field === mediaField || field === favoriteField) ? api.AssetField.WIDTH : field;
    selectField(nextField, operator);
  };

  function selectField(nextField: Modern.AssetField, operator: Filter) {
    setField(nextField);
    const example = nextField === mediaField ? api.MediaType.IMAGE : nextField === favoriteField ? true : 100;
    setValue(JSON.stringify(operator === 'within' ? [example] : example));
  }

  const read = (metadata: boolean) => action.run(async () => {
    const query = new api.Query();
    if (filter === 'eq') query.eq(field, JSON.parse(value));
    else if (filter === 'within') query.within(field, JSON.parse(value));
    else if (filter) query[filter](field, Number(value));
    if (albumId) query.album(new api.Album(albumId));
    if (sort) {
      if (!Object.values(api.AssetField).some(field => field === sort)) throw new Error('请输入有效的排序字段');
      query.orderBy({ key: sort as Modern.AssetField, ascending });
    }
    if (limit.trim()) query.limit(nonnegativeInteger(limit, '结果条数'));
    if (offset.trim()) query.offset(nonnegativeInteger(offset, '跳过条数'));
    if (metadata) {
      const result = await query.exeForMetadata();
      setAssets(result);
      return json(result);
    }

    const result = await query.exe();
    const ids = result.map(({ id }) => ({ id }));
    setAssets(ids);
    return json(ids);
  });

  return (
    <Panel title="资源查询">
      <ActionRow>
        <ActionButton label="不过滤" tone={filter === null ? 'primary' : 'secondary'} onPress={() => selectFilter(null)} />
        {FILTERS.map(operator => <ActionButton key={operator} label={operator} tone={filter === operator ? 'primary' : 'secondary'} onPress={() => selectFilter(operator)} />)}
      </ActionRow>
      {filter
        ? (
            <>
              <ActionRow>
                {fields.map(key => <ActionButton key={key} label={key} tone={field === key ? 'primary' : 'secondary'} onPress={() => selectField(key, filter)} />)}
              </ActionRow>
              <Field label="筛选值（JSON）" value={value} onChangeText={setValue} />
            </>
          )
        : null}
      <Field label="相册 ID" value={albumId} onChangeText={setAlbumId} />
      <Field label="排序字段" value={sort} onChangeText={setSort} placeholder="creationTime" />
      <DataRow label="升序" value={<Switch value={ascending} onValueChange={setAscending} accessibilityLabel="升序" />} />
      <Field label="结果条数" value={limit} onChangeText={setLimit} keyboardType="number-pad" />
      <Field label="跳过条数" value={offset} onChangeText={setOffset} keyboardType="number-pad" />
      <ActionRow>
        <ActionButton label="查询资源对象" disabled={busy} onPress={() => void read(false)} testID="media-library-next-query" />
        <ActionButton label="查询元数据" disabled={busy} onPress={() => void read(true)} tone="secondary" />
      </ActionRow>
      {assets.map(({ id }, index) => <ActionButton key={id} label={`选中资源 ${index + 1}`} onPress={() => setAssetId(id)} tone="secondary" />)}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

const GETTERS = [
  ['读取详细信息', 'getInfo'],
  ['读取文件名', 'getFilename'],
  ['读取 URI', 'getUri'],
  ['读取媒体类型', 'getMediaType'],
  ['读取宽度', 'getWidth'],
  ['读取高度', 'getHeight'],
  ['读取尺寸', 'getShape'],
  ['读取时长', 'getDuration'],
  ['读取创建时间', 'getCreationTime'],
  ['读取修改时间', 'getModificationTime'],
  ['读取 EXIF', 'getExif'],
  ['读取地理位置', 'getLocation'],
  ['读取收藏状态', 'getFavorite'],
] as const;
const IOS_GETTERS = [
  ['读取媒体子类型', 'getMediaSubtypes'],
  ['读取实况照片视频 URI', 'getLivePhotoVideoUri'],
  ['查询云端存储状态', 'getIsInCloud'],
  ['读取图片方向', 'getOrientation'],
] as const;

function AssetCard({ api, assetId, setAssetId }: { api: ModernApi } & AssetIdProps) {
  const [favorite, setFavorite] = useState(true);
  const [deleteIds, setDeleteIds] = useState('');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const asset = () => new api.Asset(assetId);
  const getters = Platform.OS === 'ios' ? [...GETTERS, ...IOS_GETTERS] : GETTERS;

  return (
    <Panel title="资源详情">
      <Field label="资源 ID" value={assetId} onChangeText={setAssetId} />
      <ActionRow>
        {getters.map(([label, method]) => (
          <ActionButton key={method} label={label} disabled={busy || !assetId} onPress={() => void action.run(async () => json(await asset()[method]()))} tone="secondary" />
        ))}
        <ActionButton label="查询所在相册" disabled={busy || !assetId} onPress={() => void action.run(async () => json((await asset().getAlbums()).map(({ id }) => ({ id }))))} tone="secondary" />
      </ActionRow>
      <DataRow label="收藏" value={<Switch value={favorite} onValueChange={setFavorite} accessibilityLabel="收藏" />} />
      <ActionRow>
        <ActionButton
          label="设置收藏状态"
          disabled={busy || !assetId}
          onPress={() => void action.run(async () => {
            await asset().setFavorite(favorite);
            return favorite ? '已收藏' : '已取消收藏';
          })}
        />
        <ActionButton
          label="删除当前资源"
          disabled={busy || !assetId}
          onPress={() => void action.run(async () => {
            await asset().delete();
            setAssetId('');
            return '已删除资源';
          })}
          tone="danger"
        />
      </ActionRow>
      <Field label="批量删除的资源 ID（逗号分隔）" value={deleteIds} onChangeText={setDeleteIds} />
      <ActionButton
        label="删除指定资源"
        disabled={busy || !listIds(deleteIds).length}
        onPress={() => void action.run(async () => {
          const ids = listIds(deleteIds);
          await api.Asset.delete(ids.map(id => new api.Asset(id)));
          if (ids.includes(assetId)) setAssetId('');
          setDeleteIds('');
          return '已删除指定资源';
        })}
        tone="danger"
      />
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function AlbumCard({ api, assetId, setAssetId, albumId, setAlbumId }: {
  api: ModernApi;
} & AssetIdProps & AlbumIdProps) {
  const [title, setTitle] = useState('相机');
  const [memberIds, setMemberIds] = useState('');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const album = () => new api.Album(albumId);
  const members = () => listIds(memberIds || assetId).map(id => new api.Asset(id));

  return (
    <Panel title="相册详情">
      <Field label="相册名称" value={title} onChangeText={setTitle} />
      <ActionRow>
        <ActionButton label="列出相册" disabled={busy} onPress={() => void action.run(async () => json((await api.Album.getAll()).map(({ id }) => ({ id }))))} />
        <ActionButton
          label="按名称查询相册"
          disabled={busy || !title}
          onPress={() => void action.run(async () => {
            const found = await api.Album.get(title);
            if (found) setAlbumId(found.id);
            return json(found ? { id: found.id } : null);
          })}
          tone="secondary"
        />
      </ActionRow>
      <Field label="相册 ID" value={albumId} onChangeText={setAlbumId} />
      <ActionRow>
        <ActionButton label="读取相册名称" disabled={busy || !albumId} onPress={() => void action.run(async () => await album().getTitle())} tone="secondary" />
        <ActionButton
          label="读取相册资源"
          disabled={busy || !albumId}
          onPress={() => void action.run(async () => {
            const result = await album().getAssets();
            if (result[0]) setAssetId(result[0].id);
            return json(result.map(({ id }) => ({ id })));
          })}
          tone="secondary"
        />
      </ActionRow>
      <Field label="资源 ID（逗号分隔）" value={memberIds} onChangeText={setMemberIds} placeholder={assetId} />
      <ActionRow>
        <ActionButton
          label="加入相册"
          disabled={busy || !albumId || !listIds(memberIds || assetId).length}
          onPress={() => void action.run(async () => {
            const assets = members();
            await album().add(assets.length === 1 ? assets[0]! : assets);
            return '资源已加入相册';
          })}
        />
        <ActionButton
          label="移出相册"
          disabled={busy || !albumId || !listIds(memberIds || assetId).length}
          onPress={() => void action.run(async () => {
            await album().removeAssets(members());
            return '资源已移出相册';
          })}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

export function MediaLibraryDemo() {
  const [modern, setModern] = useState<ModernApi>();
  const [legacy, setLegacy] = useState(true);
  const [assetId, setAssetId] = useState('');
  const [albumId, setAlbumId] = useState('');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const api = legacy ? Legacy : modern ?? Legacy;
  const assetProps = { assetId, setAssetId };
  const albumProps = { albumId, setAlbumId };

  return (
    <>
      <Panel title="媒体库接口">
        <ActionRow>
          <ActionButton
            label="默认接口"
            disabled={busy || Platform.OS === 'web'}
            tone={!legacy ? 'primary' : 'secondary'}
            onPress={() => {
              if (modern) setLegacy(false);
              else void action.run(async () => {
                setModern(await import('expo-media-library'));
                setLegacy(false);
                return '默认接口已加载';
              });
            }}
          />
          <ActionButton label="旧版接口" disabled={busy} tone={legacy ? 'primary' : 'secondary'} onPress={() => setLegacy(true)} />
        </ActionRow>
        {action.state.phase === 'error' ? <ResultPanel state={action.state} /> : null}
      </Panel>
      <MediaLibraryCards key={legacy ? 'legacy' : 'modern'} api={api} {...assetProps} {...albumProps} />
    </>
  );
}

function MediaLibraryCards({ api, ...props }: { api: MediaApi } & AssetIdProps & AlbumIdProps) {
  return (
    <>
      <MediaPermissionsCard api={api} />
      <MediaImportCard api={api} {...props} />
      {!('Asset' in api)
        ? (
            <>
              <LegacyQueryCard {...props} />
              <LegacyAssetCard {...props} />
              <LegacyAlbumCard {...props} />
            </>
          )
        : (
            <>
              <QueryCard api={api} {...props} />
              <AssetCard api={api} {...props} />
              <AlbumCard api={api} {...props} />
            </>
          )}
      <MediaEventsCard api={api} />
    </>
  );
}

const styles = StyleSheet.create({
  preview: { width: '100%', height: 200, borderRadius: 10 },
});
