const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

/**
 * Parse the APNG control chunks needed by the evidence pipeline.
 * Rejects malformed boundaries and control records before any field read.
 */
export function parseApng(animation, label = 'APNG') {
  if (!Buffer.isBuffer(animation) || animation.length < PNG_SIGNATURE.length) {
    throw new Error(`${label} is not a complete PNG.`);
  }
  if (!animation.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
    throw new Error(`${label} has an invalid PNG signature.`);
  }

  let cursor = PNG_SIGNATURE.length;
  let animationControl = null;
  let frameControlCount = 0;
  let durationMilliseconds = 0;
  let sawIend = false;

  while (cursor < animation.length) {
    if (cursor + 12 > animation.length) {
      throw new Error(`${label} has a truncated chunk header.`);
    }
    const length = animation.readUInt32BE(cursor);
    const type = animation.subarray(cursor + 4, cursor + 8).toString('ascii');
    const chunkEnd = cursor + length + 12;
    if (chunkEnd > animation.length) {
      throw new Error(`${label} has a truncated ${type} chunk.`);
    }

    if (type === 'acTL') {
      if (length !== 8 || animationControl) {
        throw new Error(`${label} has an invalid acTL chunk.`);
      }
      animationControl = {
        frames: animation.readUInt32BE(cursor + 8),
        plays: animation.readUInt32BE(cursor + 12),
      };
    } else if (type === 'fcTL') {
      if (length !== 26 || !animationControl) {
        throw new Error(`${label} has an invalid fcTL chunk.`);
      }
      frameControlCount += 1;
      const numerator = animation.readUInt16BE(cursor + 28);
      const denominator = animation.readUInt16BE(cursor + 30) || 100;
      durationMilliseconds += (numerator / denominator) * 1000;
    } else if (type === 'IEND') {
      if (length !== 0) throw new Error(`${label} has an invalid IEND chunk.`);
      sawIend = true;
      cursor = chunkEnd;
      break;
    }

    cursor = chunkEnd;
  }

  if (!sawIend) throw new Error(`${label} is missing IEND.`);
  if (cursor !== animation.length) throw new Error(`${label} contains data after IEND.`);
  if (!animationControl || animationControl.frames < 1) {
    throw new Error(`${label} is missing valid animation control.`);
  }
  if (frameControlCount !== animationControl.frames) {
    throw new Error(
      `${label} frame mismatch: acTL=${animationControl.frames}, fcTL=${frameControlCount}.`,
    );
  }

  return {
    ...animationControl,
    frameControlCount,
    durationMilliseconds,
  };
}
