import image from '@ohos.multimedia.image';

export const EXIF_KEYS: image.PropertyKey[] = [
  image.PropertyKey.BITS_PER_SAMPLE,
  image.PropertyKey.ORIENTATION,
  image.PropertyKey.IMAGE_LENGTH,
  image.PropertyKey.IMAGE_WIDTH,
  image.PropertyKey.GPS_LATITUDE,
  image.PropertyKey.GPS_LONGITUDE,
  image.PropertyKey.GPS_LATITUDE_REF,
  image.PropertyKey.GPS_LONGITUDE_REF,
  image.PropertyKey.DATE_TIME_ORIGINAL,
  image.PropertyKey.EXPOSURE_TIME,
  image.PropertyKey.SCENE_TYPE,
  image.PropertyKey.ISO_SPEED_RATINGS,
  image.PropertyKey.F_NUMBER,
  image.PropertyKey.DATE_TIME,
  image.PropertyKey.GPS_TIME_STAMP,
  image.PropertyKey.GPS_DATE_STAMP,
  image.PropertyKey.IMAGE_DESCRIPTION,
  image.PropertyKey.MAKE,
  image.PropertyKey.MODEL,
  image.PropertyKey.PHOTO_MODE,
  image.PropertyKey.SENSITIVITY_TYPE,
  image.PropertyKey.STANDARD_OUTPUT_SENSITIVITY,
  image.PropertyKey.RECOMMENDED_EXPOSURE_INDEX,
  image.PropertyKey.ISO_SPEED,
  image.PropertyKey.APERTURE_VALUE,
  image.PropertyKey.EXPOSURE_BIAS_VALUE,
  image.PropertyKey.METERING_MODE,
  image.PropertyKey.LIGHT_SOURCE,
  image.PropertyKey.FLASH,
  image.PropertyKey.FOCAL_LENGTH,
  image.PropertyKey.USER_COMMENT,
  image.PropertyKey.PIXEL_X_DIMENSION,
  image.PropertyKey.PIXEL_Y_DIMENSION,
  image.PropertyKey.WHITE_BALANCE,
  image.PropertyKey.FOCAL_LENGTH_IN_35_MM_FILM,
  image.PropertyKey.CAPTURE_MODE,
  image.PropertyKey.PHYSICAL_APERTURE,
  image.PropertyKey.ROLL_ANGLE,
  image.PropertyKey.PITCH_ANGLE,
  image.PropertyKey.SCENE_FOOD_CONF,
  image.PropertyKey.SCENE_STAGE_CONF,
  image.PropertyKey.SCENE_BLUE_SKY_CONF,
  image.PropertyKey.SCENE_GREEN_PLANT_CONF,
  image.PropertyKey.SCENE_BEACH_CONF,
  image.PropertyKey.SCENE_SNOW_CONF,
  image.PropertyKey.SCENE_SUNSET_CONF,
  image.PropertyKey.SCENE_FLOWERS_CONF,
  image.PropertyKey.SCENE_NIGHT_CONF,
  image.PropertyKey.SCENE_TEXT_CONF,
  image.PropertyKey.FACE_COUNT,
  image.PropertyKey.FOCUS_MODE,
  image.PropertyKey.COMPRESSION,
  image.PropertyKey.PHOTOMETRIC_INTERPRETATION,
  image.PropertyKey.STRIP_OFFSETS,
  image.PropertyKey.SAMPLES_PER_PIXEL,
  image.PropertyKey.ROWS_PER_STRIP,
  image.PropertyKey.STRIP_BYTE_COUNTS,
  image.PropertyKey.X_RESOLUTION,
  image.PropertyKey.Y_RESOLUTION,
  image.PropertyKey.PLANAR_CONFIGURATION,
  image.PropertyKey.RESOLUTION_UNIT,
  image.PropertyKey.TRANSFER_FUNCTION,
  image.PropertyKey.SOFTWARE,
  image.PropertyKey.ARTIST,
  image.PropertyKey.WHITE_POINT,
  image.PropertyKey.PRIMARY_CHROMATICITIES,
  image.PropertyKey.YCBCR_COEFFICIENTS,
  image.PropertyKey.YCBCR_SUB_SAMPLING,
  image.PropertyKey.YCBCR_POSITIONING,
  image.PropertyKey.REFERENCE_BLACK_WHITE,
  image.PropertyKey.COPYRIGHT,
  image.PropertyKey.JPEG_INTERCHANGE_FORMAT,
  image.PropertyKey.JPEG_INTERCHANGE_FORMAT_LENGTH,
  image.PropertyKey.EXPOSURE_PROGRAM,
  image.PropertyKey.SPECTRAL_SENSITIVITY,
  image.PropertyKey.OECF,
  image.PropertyKey.EXIF_VERSION,
  image.PropertyKey.DATE_TIME_DIGITIZED,
  image.PropertyKey.COMPONENTS_CONFIGURATION,
  image.PropertyKey.SHUTTER_SPEED,
  image.PropertyKey.BRIGHTNESS_VALUE,
  image.PropertyKey.MAX_APERTURE_VALUE,
  image.PropertyKey.SUBJECT_DISTANCE,
  image.PropertyKey.SUBJECT_AREA,
  image.PropertyKey.MAKER_NOTE,
  image.PropertyKey.SUBSEC_TIME,
  image.PropertyKey.SUBSEC_TIME_ORIGINAL,
  image.PropertyKey.SUBSEC_TIME_DIGITIZED,
  image.PropertyKey.FLASHPIX_VERSION,
  image.PropertyKey.COLOR_SPACE,
  image.PropertyKey.RELATED_SOUND_FILE,
  image.PropertyKey.FLASH_ENERGY,
  image.PropertyKey.SPATIAL_FREQUENCY_RESPONSE,
  image.PropertyKey.FOCAL_PLANE_X_RESOLUTION,
  image.PropertyKey.FOCAL_PLANE_Y_RESOLUTION,
  image.PropertyKey.FOCAL_PLANE_RESOLUTION_UNIT,
  image.PropertyKey.SUBJECT_LOCATION,
  image.PropertyKey.EXPOSURE_INDEX,
  image.PropertyKey.SENSING_METHOD,
  image.PropertyKey.FILE_SOURCE,
  image.PropertyKey.CFA_PATTERN,
  image.PropertyKey.CUSTOM_RENDERED,
  image.PropertyKey.EXPOSURE_MODE,
  image.PropertyKey.DIGITAL_ZOOM_RATIO,
  image.PropertyKey.SCENE_CAPTURE_TYPE,
  image.PropertyKey.GAIN_CONTROL,
  image.PropertyKey.CONTRAST,
  image.PropertyKey.SATURATION,
  image.PropertyKey.SHARPNESS,
  image.PropertyKey.DEVICE_SETTING_DESCRIPTION,
  image.PropertyKey.SUBJECT_DISTANCE_RANGE,
  image.PropertyKey.IMAGE_UNIQUE_ID,
  image.PropertyKey.GPS_VERSION_ID,
  image.PropertyKey.GPS_ALTITUDE_REF,
  image.PropertyKey.GPS_ALTITUDE,
  image.PropertyKey.GPS_SATELLITES,
  image.PropertyKey.GPS_STATUS,
  image.PropertyKey.GPS_MEASURE_MODE,
  image.PropertyKey.GPS_DOP,
  image.PropertyKey.GPS_SPEED_REF,
  image.PropertyKey.GPS_SPEED,
  image.PropertyKey.GPS_TRACK_REF,
  image.PropertyKey.GPS_TRACK,
  image.PropertyKey.GPS_IMG_DIRECTION_REF,
  image.PropertyKey.GPS_IMG_DIRECTION,
  image.PropertyKey.GPS_MAP_DATUM,
  image.PropertyKey.GPS_DEST_LATITUDE_REF,
  image.PropertyKey.GPS_DEST_LATITUDE,
  image.PropertyKey.GPS_DEST_LONGITUDE_REF,
  image.PropertyKey.GPS_DEST_LONGITUDE,
  image.PropertyKey.GPS_DEST_BEARING_REF,
  image.PropertyKey.GPS_DEST_BEARING,
  image.PropertyKey.GPS_DEST_DISTANCE_REF,
  image.PropertyKey.GPS_DEST_DISTANCE,
  image.PropertyKey.GPS_PROCESSING_METHOD,
  image.PropertyKey.GPS_AREA_INFORMATION,
  image.PropertyKey.GPS_DIFFERENTIAL,
  image.PropertyKey.BODY_SERIAL_NUMBER,
  image.PropertyKey.CAMERA_OWNER_NAME,
  image.PropertyKey.COMPOSITE_IMAGE,
  image.PropertyKey.COMPRESSED_BITS_PER_PIXEL,
  image.PropertyKey.DNG_VERSION,
  image.PropertyKey.DEFAULT_CROP_SIZE,
  image.PropertyKey.GAMMA,
  image.PropertyKey.ISO_SPEED_LATITUDE_YYY,
  image.PropertyKey.ISO_SPEED_LATITUDE_ZZZ,
  image.PropertyKey.LENS_MAKE,
  image.PropertyKey.LENS_MODEL,
  image.PropertyKey.LENS_SERIAL_NUMBER,
  image.PropertyKey.LENS_SPECIFICATION,
  image.PropertyKey.NEW_SUBFILE_TYPE,
  image.PropertyKey.OFFSET_TIME,
  image.PropertyKey.OFFSET_TIME_DIGITIZED,
  image.PropertyKey.OFFSET_TIME_ORIGINAL,
  image.PropertyKey.SOURCE_EXPOSURE_TIMES_OF_COMPOSITE_IMAGE,
  image.PropertyKey.SOURCE_IMAGE_NUMBER_OF_COMPOSITE_IMAGE,
  image.PropertyKey.SUBFILE_TYPE,
  image.PropertyKey.GPS_H_POSITIONING_ERROR,
  image.PropertyKey.PHOTOGRAPHIC_SENSITIVITY,
  image.PropertyKey.BURST_NUMBER,
  image.PropertyKey.FACE_CONF,
  image.PropertyKey.FACE_LEYE_CENTER,
  image.PropertyKey.FACE_MOUTH_CENTER,
  image.PropertyKey.FACE_POINTER,
  image.PropertyKey.FACE_RECT,
  image.PropertyKey.FACE_REYE_CENTER,
  image.PropertyKey.FACE_SMILE_SCORE,
  image.PropertyKey.FACE_VERSION,
  image.PropertyKey.FRONT_CAMERA,
  image.PropertyKey.SCENE_POINTER,
  image.PropertyKey.SCENE_VERSION,
  image.PropertyKey.IS_XMAGE_SUPPORTED,
  image.PropertyKey.XMAGE_MODE,
  image.PropertyKey.XMAGE_LEFT,
  image.PropertyKey.XMAGE_TOP,
  image.PropertyKey.XMAGE_RIGHT,
  image.PropertyKey.XMAGE_BOTTOM,
  image.PropertyKey.CLOUD_ENHANCEMENT_MODE,
  image.PropertyKey.WIND_SNAPSHOT_MODE,
  image.PropertyKey.GIF_LOOP_COUNT,
];

const EXIF_INTEGER_KEYS: image.PropertyKey[] = [
  image.PropertyKey.BITS_PER_SAMPLE,
  image.PropertyKey.COMPRESSION,
  image.PropertyKey.IMAGE_LENGTH,
  image.PropertyKey.IMAGE_WIDTH,
  image.PropertyKey.JPEG_INTERCHANGE_FORMAT,
  image.PropertyKey.JPEG_INTERCHANGE_FORMAT_LENGTH,
  image.PropertyKey.ORIENTATION,
  image.PropertyKey.PHOTOMETRIC_INTERPRETATION,
  image.PropertyKey.PLANAR_CONFIGURATION,
  image.PropertyKey.RESOLUTION_UNIT,
  image.PropertyKey.ROWS_PER_STRIP,
  image.PropertyKey.SAMPLES_PER_PIXEL,
  image.PropertyKey.STRIP_BYTE_COUNTS,
  image.PropertyKey.STRIP_OFFSETS,
  image.PropertyKey.TRANSFER_FUNCTION,
  image.PropertyKey.YCBCR_POSITIONING,
  image.PropertyKey.YCBCR_SUB_SAMPLING,
  image.PropertyKey.COLOR_SPACE,
  image.PropertyKey.CONTRAST,
  image.PropertyKey.CUSTOM_RENDERED,
  image.PropertyKey.EXPOSURE_MODE,
  image.PropertyKey.EXPOSURE_PROGRAM,
  image.PropertyKey.FLASH,
  image.PropertyKey.FOCAL_LENGTH_IN_35_MM_FILM,
  image.PropertyKey.FOCAL_PLANE_RESOLUTION_UNIT,
  image.PropertyKey.GAIN_CONTROL,
  image.PropertyKey.ISO_SPEED_RATINGS,
  image.PropertyKey.LIGHT_SOURCE,
  image.PropertyKey.METERING_MODE,
  image.PropertyKey.NEW_SUBFILE_TYPE,
  image.PropertyKey.PIXEL_X_DIMENSION,
  image.PropertyKey.PIXEL_Y_DIMENSION,
  image.PropertyKey.SATURATION,
  image.PropertyKey.SCENE_CAPTURE_TYPE,
  image.PropertyKey.SENSING_METHOD,
  image.PropertyKey.SHARPNESS,
  image.PropertyKey.SUBFILE_TYPE,
  image.PropertyKey.SUBJECT_AREA,
  image.PropertyKey.SUBJECT_DISTANCE_RANGE,
  image.PropertyKey.SUBJECT_LOCATION,
  image.PropertyKey.WHITE_BALANCE,
  image.PropertyKey.GPS_ALTITUDE_REF,
  image.PropertyKey.GPS_DIFFERENTIAL,
  image.PropertyKey.DNG_VERSION,
  image.PropertyKey.DEFAULT_CROP_SIZE,
];

const EXIF_DOUBLE_KEYS: image.PropertyKey[] = [
  image.PropertyKey.PRIMARY_CHROMATICITIES,
  image.PropertyKey.REFERENCE_BLACK_WHITE,
  image.PropertyKey.WHITE_POINT,
  image.PropertyKey.X_RESOLUTION,
  image.PropertyKey.YCBCR_COEFFICIENTS,
  image.PropertyKey.Y_RESOLUTION,
  image.PropertyKey.APERTURE_VALUE,
  image.PropertyKey.BRIGHTNESS_VALUE,
  image.PropertyKey.COMPRESSED_BITS_PER_PIXEL,
  image.PropertyKey.DIGITAL_ZOOM_RATIO,
  image.PropertyKey.EXPOSURE_BIAS_VALUE,
  image.PropertyKey.EXPOSURE_INDEX,
  image.PropertyKey.EXPOSURE_TIME,
  image.PropertyKey.F_NUMBER,
  image.PropertyKey.FLASH_ENERGY,
  image.PropertyKey.FOCAL_LENGTH,
  image.PropertyKey.FOCAL_PLANE_X_RESOLUTION,
  image.PropertyKey.FOCAL_PLANE_Y_RESOLUTION,
  image.PropertyKey.MAX_APERTURE_VALUE,
  image.PropertyKey.SHUTTER_SPEED,
  image.PropertyKey.SUBJECT_DISTANCE,
  image.PropertyKey.GPS_ALTITUDE,
  image.PropertyKey.GPS_DOP,
  image.PropertyKey.GPS_DEST_BEARING,
  image.PropertyKey.GPS_DEST_DISTANCE,
  image.PropertyKey.GPS_DEST_LATITUDE,
  image.PropertyKey.GPS_DEST_LONGITUDE,
  image.PropertyKey.GPS_H_POSITIONING_ERROR,
  image.PropertyKey.GPS_IMG_DIRECTION,
  image.PropertyKey.GPS_LATITUDE,
  image.PropertyKey.GPS_LONGITUDE,
  image.PropertyKey.GPS_SPEED,
  image.PropertyKey.GPS_TRACK,
];

function rationalNumber(value: string): number | undefined {
  const parts = value.trim().split('/');
  const numerator = Number(parts[0]);
  const denominator = parts.length > 1 ? Number(parts[1]) : 1;
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator === 0) return undefined;

  return numerator / denominator;
}

function coordinate(value?: string | null, reference?: string | null): number | undefined {
  if (value === undefined || value === null) return undefined;

  const parts = value.split(',').map((part: string): number | undefined => rationalNumber(part));
  if (parts.length < 3 || parts.some((part: number | undefined): boolean => part === undefined)) return undefined;

  const result = (parts[0] ?? 0) + (parts[1] ?? 0) / 60 + (parts[2] ?? 0) / 3600;
  return reference === 'S' || reference === 'W' ? -result : result;
}

function rationalString(value: number): string {
  const denominator = 1_000_000;
  return `${Math.round(value * denominator)}/${denominator}`;
}

function coordinateString(value: number): string {
  const absolute = Math.abs(value);
  const degrees = Math.floor(absolute);
  const minutesValue = (absolute - degrees) * 60;
  const minutes = Math.floor(minutesValue);
  const seconds = (minutesValue - minutes) * 60;
  return `${degrees}/1,${minutes}/1,${rationalString(seconds)}`;
}

export function decodeExifProperties(properties: Record<image.PropertyKey, string | null>): Record<string, ESObject> {
  const result: Record<string, ESObject> = {};

  EXIF_KEYS.forEach((key: image.PropertyKey): void => {
    const raw = properties[key];
    if (raw === undefined || raw === null) return;

    if (key === image.PropertyKey.GPS_LATITUDE) {
      result[key] = coordinate(raw, properties[image.PropertyKey.GPS_LATITUDE_REF]) ?? raw;
    } else if (key === image.PropertyKey.GPS_LONGITUDE) {
      result[key] = coordinate(raw, properties[image.PropertyKey.GPS_LONGITUDE_REF]) ?? raw;
    } else if (key === image.PropertyKey.GPS_ALTITUDE) {
      const altitude = rationalNumber(raw);
      result[key] = altitude === undefined ? raw : properties[image.PropertyKey.GPS_ALTITUDE_REF] === '1' ? -altitude : altitude;
    } else if (EXIF_INTEGER_KEYS.includes(key)) {
      const value = Number.parseInt(raw, 10);
      result[key] = Number.isFinite(value) ? value : raw;
    } else if (EXIF_DOUBLE_KEYS.includes(key)) {
      result[key] = rationalNumber(raw) ?? raw;
    } else {
      result[key] = raw;
    }
  });

  return result;
}

export function encodeExifMetadata(metadata?: Record<string, ESObject>): Record<image.PropertyKey, string | null> {
  const records = {} as Record<image.PropertyKey, string | null>;
  if (metadata === undefined) return records;

  Object.keys(metadata).forEach((name: string): void => {
    const key = name as image.PropertyKey;
    const value: ESObject = metadata[name];
    if (!EXIF_KEYS.includes(key) || value === undefined || value === null) return;

    if (typeof value !== 'number' || !Number.isFinite(value)) {
      records[key] = String(value);
      return;
    }

    if (key === image.PropertyKey.GPS_LATITUDE || key === image.PropertyKey.GPS_DEST_LATITUDE) {
      records[key] = coordinateString(value);
      const reference = key === image.PropertyKey.GPS_LATITUDE ? image.PropertyKey.GPS_LATITUDE_REF : image.PropertyKey.GPS_DEST_LATITUDE_REF;
      records[reference] = value < 0 ? 'S' : 'N';
    } else if (key === image.PropertyKey.GPS_LONGITUDE || key === image.PropertyKey.GPS_DEST_LONGITUDE) {
      records[key] = coordinateString(value);
      const reference = key === image.PropertyKey.GPS_LONGITUDE ? image.PropertyKey.GPS_LONGITUDE_REF : image.PropertyKey.GPS_DEST_LONGITUDE_REF;
      records[reference] = value < 0 ? 'W' : 'E';
    } else if (key === image.PropertyKey.GPS_ALTITUDE) {
      records[key] = rationalString(Math.abs(value));
      records[image.PropertyKey.GPS_ALTITUDE_REF] = value < 0 ? '1' : '0';
    } else if (EXIF_DOUBLE_KEYS.includes(key)) {
      records[key] = rationalString(value);
    } else {
      records[key] = String(Math.trunc(value));
    }
  });

  return records;
}
