# Importing Gwyddion text exports (`*.txt`)

FiberApp reads the ASCII files written by Gwyddion, so that AFM images which
are levelled, filtered or cropped in Gwyddion can be tracked directly, without
an intermediate TIF and without losing the height calibration.

Select the file with `FiberApp -> Open Image`; any file with the `txt`
extension is routed to the Gwyddion reader.

## Exporting from Gwyddion

In Gwyddion use `File -> Save As...` and choose the file type
*ASCII data matrix* (`.txt`), then enable **Add informational header** in the
export dialogue. The resulting file looks as follows:

```
# Channel: Height
# Width: 2.000000 µm
# Height: 1.600000 µm
# Value units: m
1.88595e-11	-1.98157e-11	9.60634e-11	...
...
```

The header carries the lateral size of the scan and the unit of the values, so
no further input is required and the imported image is scaled in nanometres in
all three directions.

The reader also accepts:

* a bare matrix of values exported **without** the informational header. Since
  such a file carries no calibration, FiberApp asks for the image width in nm
  and for the unit of the values. Gwyddion writes the values of a channel in
  base SI units, so the unit is `m` for a height channel;
* a three-column `x y z` text file (Gwyddion's XYZ export), provided that the
  points form a complete regular grid;
* values separated by commas or semicolons instead of whitespace;
* masked or otherwise invalid points exported as `NaN`. They are replaced by
  the minimum of the image and a warning reports how many there were, so that
  those areas can be avoided during tracking;
* channels whose values are not a length (for example a `V` channel). The unit
  to be used is then asked for, and the resulting heights are only as
  meaningful as that choice.

## Conventions used by the reader

**Lateral scale.** Gwyddion reports the full field size, therefore the pixel
size is `scaleXY = width / sizeX`, in line with the definition of `scaleXY`
in `@ImageData/ImageData.m` and with the WLC image generator. If the pixels of
the exported field are not square (`width/sizeX` and `height/sizeY` differ by
more than 1%), a warning is shown and the x-scale is applied to both
directions, because FiberApp describes an image by a single lateral scale.

**Height scale.** FiberApp stores an image as integer intensity units together
with a factor `scaleZ` that converts them to nanometres. The imported heights
are therefore quantized with a step

```
scaleZ = round2n(z_range / 4096)
```

which is chosen so that:

* the step is orders of magnitude finer than the z-noise of an AFM image
  (0.001 nm for a typical 5 nm range, against ~0.05 nm of RMS roughness), so
  the quantization does not contribute to the measured height distributions;
* the image spans about 4096 intensity units, which keeps the doubled image
  gradient inside the `int16` range used by `utility.gradient2Dx2`. A wider
  span would clip the gradient at the steepest edges and bias the active
  contour fit.

The zero of the height scale is the zero of the exported channel, i.e. the
levelling performed in Gwyddion is preserved: a substrate levelled to zero in
Gwyddion stays at zero intensity, fibrils take positive values, and the
`A*` cost function, which is inversely proportional to the pixel value, behaves
as intended. `Image -> Set Zero Level` can still be used to re-reference the
heights to a background area of the image, and `Image -> Remove Surface`
remains available for images that were not flattened beforehand.

**Row order.** The first data row of the file is the top row of the image, as
displayed in Gwyddion.

## Implementation

| File | Role |
| --- | --- |
| `+utility/parseGwyddionText.m` | reads the file and its header, returns the raw values and the scales found; contains no GUI code |
| `+utility/lengthUnitToNm.m` | converts a unit string (`m`, `µm`, `nm`, `Å`, ...) to nanometres |
| `+utility/readGwyddionImage.m` | asks the user for whatever the file does not provide, converts the data to the image representation used by FiberApp |
| `+FiberAppGUI/OpenImage.m` | file filter and dispatch on the `txt` extension |
