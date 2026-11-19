import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';

/** An owned copy of the confirmation crop; never borrows a page's PixelMap across await. */
export class FacePhoto {
  readonly rgba: ArrayBuffer;
  readonly width: number;
  readonly height: number;
  constructor(rgba: ArrayBuffer, width: number, height: number) {
    this.rgba = rgba; this.width = width; this.height = height;
  }
}

/** Demo-private, confirmed crops only. Backup is disabled by the Demo's backup profile. */
export enum FacePhotoLibrary { SEARCH = 'search', REFERENCE = 'reference' }

export class FacePhotoStore {
  // Shared queue protects each crop's temporary-file replacement from overlapping writes/deletes.
  private static operations: Promise<void> = Promise.resolve();

  // Copy pixels synchronously before the confirmation page can replace or release its PixelMap.
  static capture(pixelMap: image.PixelMap | undefined): FacePhoto | undefined {
    if (pixelMap === undefined) return undefined;
    try {
      const size: image.Size = pixelMap.getImageInfoSync().size;
      if (size.width < 1 || size.height < 1 || size.width > 720 || size.height > 720) return undefined;
      const bytes: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      pixelMap.readPixelsToBufferSync(bytes);
      return new FacePhoto(bytes, size.width, size.height);
    } catch (_) { return undefined; }
  }

  private static async path(context: common.UIAbilityContext, id: string, library: FacePhotoLibrary, create: boolean): Promise<string> {
    if (id.length === 0 || id.includes('\u0000')) throw new Error('Invalid Face ID');
    let key: string = /^[0-9]+$/.test(id) ? id : '~';
    if (key === '~') {
      const bytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(id);
      for (let index: number = 0; index < bytes.length; ++index) key += bytes[index].toString(16).padStart(2, '0');
    }
    let directory: string = context.filesDir + '/face-photos-v1/' + library;
    while (key.length > 120) { directory += '/' + key.slice(0, 120); key = key.slice(120); }
    if (create) {
      try { await fileIo.mkdir(directory, true); }
      catch (_) {
        const existing: fileIo.Stat = await fileIo.stat(directory);
        if (!existing.isDirectory()) throw new Error('Invalid photo directory');
      }
    }
    return directory + '/' + key + '.jpg';
  }

  private static enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const result: Promise<T> = FacePhotoStore.operations.then(operation);
    FacePhotoStore.operations = result.then((): void => {}, (): void => {});
    return result;
  }

  static save(context: common.UIAbilityContext, id: string, photo: FacePhoto | undefined,
    library: FacePhotoLibrary = FacePhotoLibrary.SEARCH): Promise<void> {
    return FacePhotoStore.enqueue<void>(async (): Promise<void> => {
      let path: string = '';
      let temporary: string = '';
      let pixels: image.PixelMap | undefined = undefined;
      let packer: image.ImagePacker | undefined = undefined;
      let file: fileIo.File | undefined = undefined;
      let jpeg: ArrayBuffer | undefined = undefined;
      try {
        path = await FacePhotoStore.path(context, id, library, true);
        if (photo === undefined) throw new Error('No confirmed crop');
        pixels = await image.createPixelMap(photo.rgba, { size: { width: photo.width, height: photo.height },
          srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888, editable: false });
        packer = image.createImagePacker();
        jpeg = await packer.packToData(pixels, { format: 'image/jpeg', quality: 95 });
        // One serialized temporary file, replaced/removed within the same operation.
        temporary = path + '.tmp';
        file = await fileIo.open(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        let offset: number = 0;
        while (offset < jpeg.byteLength) {
          const written: number = await fileIo.write(file.fd, jpeg.slice(offset));
          if (written <= 0) throw new Error('Photo write failed');
          offset += written;
        }
        await fileIo.fsync(file.fd);
        await fileIo.close(file); file = undefined;
        await fileIo.rename(temporary, path);
      } catch (_) {
        // The feature has committed: discard the previous photo on replacement failure.
        if (path.length > 0) { try { await fileIo.unlink(path); } catch (_) {} }
      } finally {
        if (file !== undefined) { try { await fileIo.close(file); } catch (_) {} }
        if (temporary.length > 0) { try { await fileIo.unlink(temporary); } catch (_) {} }
        if (packer !== undefined) { try { await packer.release(); } catch (_) {} }
        if (pixels !== undefined) { try { await pixels.release(); } catch (_) {} }
        if (jpeg !== undefined) new Uint8Array(jpeg).fill(0);
        if (photo !== undefined) new Uint8Array(photo.rgba).fill(0);
      }
    });
  }

  static remove(context: common.UIAbilityContext, id: string, library: FacePhotoLibrary = FacePhotoLibrary.SEARCH): Promise<void> {
    return FacePhotoStore.removeMany(context, [id], library);
  }

  static removeMany(context: common.UIAbilityContext, ids: string[], library: FacePhotoLibrary = FacePhotoLibrary.SEARCH): Promise<void> {
    return FacePhotoStore.enqueue<void>(async (): Promise<void> => {
      for (const id of ids) {
        try { await fileIo.unlink(await FacePhotoStore.path(context, id, library, false)); } catch (_) {}
      }
    });
  }

  static thumbnail(context: common.UIAbilityContext, id: string, library: FacePhotoLibrary = FacePhotoLibrary.SEARCH): Promise<image.PixelMap | undefined> {
    return FacePhotoStore.enqueue<image.PixelMap | undefined>(async (): Promise<image.PixelMap | undefined> => {
      let source: image.ImageSource | undefined = undefined;
      try {
        const path: string = await FacePhotoStore.path(context, id, library, false);
        const info: fileIo.Stat = await fileIo.stat(path);
        if (info.size > 1024 * 1024) return undefined;
        source = image.createImageSource(path);
        const size: image.Size = (await source.getImageInfo()).size;
        if (size.width < 1 || size.height < 1 || size.width > 720 || size.height > 720) return undefined;
        return await source.createPixelMap({ desiredSize: { width: 96, height: 96 } });
      } catch (_) { return undefined; }
      finally { if (source !== undefined) { try { await source.release(); } catch (_) {} } }
    });
  }
}

@Component
export struct FacePhotoThumbnail {
  @Prop @Watch('reload') faceId: string = '';
  @Prop @Watch('reload') library: FacePhotoLibrary = FacePhotoLibrary.SEARCH;
  diameter: number = 42;
  circular: boolean = false;
  @State private photo: image.PixelMap | undefined = undefined;
  private generation: number = 0;
  private visible: boolean = false;

  aboutToAppear(): void { this.visible = true; this.reload(); }
  aboutToDisappear(): void {
    this.visible = false; ++this.generation;
    const previous: image.PixelMap | undefined = this.photo;
    this.photo = undefined;
    if (previous !== undefined) previous.release().catch((): void => {});
  }
  private async reload(): Promise<void> {
    if (!this.visible) return;
    const token: number = ++this.generation;
    const old: image.PixelMap | undefined = this.photo;
    this.photo = undefined;
    if (old !== undefined) await old.release();
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const loaded: image.PixelMap | undefined = await FacePhotoStore.thumbnail(context, this.faceId, this.library);
    if (!this.visible || token !== this.generation) { if (loaded !== undefined) await loaded.release(); return; }
    this.photo = loaded;
  }
  build() {
    Stack() {
      if (this.photo !== undefined) {
        Image(this.photo).width(this.diameter).height(this.diameter).objectFit(ImageFit.Cover)
      } else {
        Image($r('app.media.ic_home_enroll')).width(this.circular ? 28 : 22).height(this.circular ? 28 : 22)
          .fillColor(this.circular ? '#077A63' : '#FFFFFF')
      }
    }.width(this.diameter).height(this.diameter).backgroundColor(this.circular ? '#E6F2ED' : '#243247')
      .borderRadius(this.circular ? this.diameter / 2 : 9).clip(true)
  }
}
