import { DetectedFace, FaceDetectionResult } from 'hiface';
import { OutlinedCanvasText } from '../ui/OutlinedCanvasText';
import { PreviewCoordinateTransform } from '../ui/PreviewCoordinateTransform';

// 与 Android FaceDetectionOverlayView 的轮廓索引及五点样式保持一致。
const CONTOURS: number[][] = [
  [61, 146, 146, 91, 91, 181, 181, 84, 84, 17, 17, 314, 314, 405, 405, 321, 321, 375, 375, 291, 61, 185, 185, 40, 40, 39, 39, 37, 37, 0, 0, 267, 267, 269, 269, 270, 270, 409, 409, 291, 78, 95, 95, 88, 88, 178, 178, 87, 87, 14, 14, 317, 317, 402, 402, 318, 318, 324, 324, 308, 78, 191, 191, 80, 80, 81, 81, 82, 82, 13, 13, 312, 312, 311, 311, 310, 310, 415, 415, 308],
  [263, 249, 249, 390, 390, 373, 373, 374, 374, 380, 380, 381, 381, 382, 382, 362, 263, 466, 466, 388, 388, 387, 387, 386, 386, 385, 385, 384, 384, 398, 398, 362],
  [33, 7, 7, 163, 163, 144, 144, 145, 145, 153, 153, 154, 154, 155, 155, 133, 33, 246, 246, 161, 161, 160, 160, 159, 159, 158, 158, 157, 157, 173, 173, 133],
  [10, 338, 338, 297, 297, 332, 332, 284, 284, 251, 251, 389, 389, 356, 356, 454, 454, 323, 323, 361, 361, 288, 288, 397, 397, 365, 365, 379, 379, 378, 378, 400, 400, 377, 377, 152, 152, 148, 148, 176, 176, 149, 149, 150, 150, 136, 136, 172, 172, 58, 58, 132, 132, 93, 93, 234, 234, 127, 127, 162, 162, 21, 21, 54, 54, 103, 103, 67, 67, 109, 109, 10],
  [168, 6, 6, 197, 197, 195, 195, 5, 5, 4, 4, 1, 1, 19, 19, 94, 94, 2, 98, 97, 97, 2, 2, 326, 326, 327]
];

export class FaceDetectionOverlay {
  static draw(context: CanvasRenderingContext2D, detection: FaceDetectionResult,
    width: number, height: number, mirrored: boolean): void {
    const transform: PreviewCoordinateTransform = PreviewCoordinateTransform.fit(
      detection.imageWidth, detection.imageHeight, width, height, mirrored);
    context.save();
    // Canvas 字体必须显式使用 vp；11px 是物理像素，无法匹配 Android 的 11sp 默认字号。
    context.font = 'bold 11vp sans-serif';
    context.lineWidth = 2;
    for (let index: number = 0; index < detection.faces.length; index += 1) {
      const face = detection.faces[index];
      context.strokeStyle = '#9C27B0';
      const sourceX: number = face.x - face.width * 0.1;
      const sourceY: number = face.y + face.height * 0.05 / 9;
      const faceWidth: number = face.width * 1.2 * transform.scale;
      const faceHeight: number = face.height * (1 + 0.05 - 0.05 / 9) * transform.scale;
      const x: number = transform.rectX(sourceX, face.width * 1.2);
      const y: number = transform.y(sourceY);
      context.strokeRect(x, y, faceWidth, faceHeight);
      let label: string = `${Math.round(face.confidence * 100)}%`;
      if (face.headPose !== undefined) {
        label += `,  P: ${Math.round(face.headPose.pitch)},  Y: ${Math.round(face.headPose.yaw)},  R: ${Math.round(face.headPose.roll)}`;
      }
      const labelWidth: number = context.measureText(label).width;
      const labelX: number = Math.max(6, Math.min(x, width - labelWidth - 6));
      const baseline: number = Math.max(17, y - 6);
      OutlinedCanvasText.draw(context, label, labelX, baseline);
      FaceDetectionOverlay.drawDetails(context, face, transform);
    }
    context.restore();
  }

  static drawDetails(context: CanvasRenderingContext2D, face: DetectedFace,
    transform: PreviewCoordinateTransform): void {
    const mesh = face.mesh;
    context.save();
    if (mesh !== undefined) {
      context.beginPath();
      for (let group: number = 0; group < CONTOURS.length; group++) {
        const connections: number[] = CONTOURS[group];
        const eye: boolean = group === 1 || group === 2;
        let centerX: number = 0;
        let centerY: number = 0;
        if (eye) {
          let minX: number = Infinity;
          let maxX: number = -Infinity;
          let minY: number = Infinity;
          let maxY: number = -Infinity;
          for (const index of connections) {
            if (index >= mesh.length) continue;
            minX = Math.min(minX, mesh[index].x); maxX = Math.max(maxX, mesh[index].x);
            minY = Math.min(minY, mesh[index].y); maxY = Math.max(maxY, mesh[index].y);
          }
          centerX = (minX + maxX) / 2;
          centerY = (minY + maxY) / 2;
        }
        for (let i: number = 0; i < connections.length; i += 2) {
          const start: number = connections[i];
          const end: number = connections[i + 1];
          if (start >= mesh.length || end >= mesh.length) continue;
          const x1: number = eye ? centerX + (mesh[start].x - centerX) * 1.4 : mesh[start].x;
          const y1: number = eye ? centerY + (mesh[start].y - centerY) * 1.4 : mesh[start].y;
          const x2: number = eye ? centerX + (mesh[end].x - centerX) * 1.4 : mesh[end].x;
          const y2: number = eye ? centerY + (mesh[end].y - centerY) * 1.4 : mesh[end].y;
          context.moveTo(transform.x(x1), transform.y(y1));
          context.lineTo(transform.x(x2), transform.y(y2));
        }
      }
      context.lineCap = 'round';
      context.strokeStyle = 'rgba(0,45,52,0.745)'; context.lineWidth = 3; context.stroke();
      context.strokeStyle = '#00BCCD'; context.lineWidth = 1.5; context.stroke();
    }
    context.fillStyle = '#9C27B0';
    for (const point of face.landmarks) {
      context.beginPath();
      context.arc(transform.x(point.x), transform.y(point.y), 2.2, 0, Math.PI * 2);
      context.fill();
    }
    context.restore();
  }
}
