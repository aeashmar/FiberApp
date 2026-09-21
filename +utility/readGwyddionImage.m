%READGWYDDIONIMAGE Read a Gwyddion ASCII (*.txt) export of an SPM image
%
%   Accepts the plain text matrix written by Gwyddion ("Export Text Data"),
%   with or without the informational header, as well as a three-column XYZ
%   text file sampled on a regular grid.
%
%   Gwyddion writes the values of a channel in base SI units (m for a
%   height channel), while FiberApp stores an image as integer intensity
%   units together with the scaleZ factor that converts them to nanometers.
%   The heights are therefore quantized here with a step scaleZ chosen so
%   that the data span N_LEVELS intensity units. The step is orders of
%   magnitude smaller than the z-noise of an AFM image, and the resulting
%   span is small enough for utility.gradient2Dx2, which casts the image
%   gradient to int16, not to saturate on the steepest edges.
%
%   The zero of the imported height scale is the zero of the exported
%   channel, i.e. the leveling performed in Gwyddion is preserved.

% Copyright (c) 2011-2014 ETH Zurich, 2015 FiberApp Contributors. All rights reserved.
% Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

function [im, sizeX, sizeY, sizeX_nm, sizeY_nm, scaleXY, scaleZ] = ...
    readGwyddionImage(filePath, fileName)
% Initialize variables with empty values
im = [];
sizeX = [];
sizeY = [];
sizeX_nm = [];
sizeY_nm = [];
scaleXY = [];
scaleZ = [];

N_LEVELS = 4096; % number of intensity units over the height range

info = utility.parseGwyddionText(fullfile(filePath, fileName));
if ~info.ok
    errordlg(info.message, 'Open Image');
    return
end

z = info.z;
sizeX = info.sizeX;
sizeY = info.sizeY;

% Handle masked or invalid points, which Gwyddion exports as NaN
invalid = ~isfinite(z);
if any(invalid(:))
    if all(invalid(:))
        errordlg('Selected file does not contain any valid data.', 'Open Image');
        im = [];
        return
    end
    z(invalid) = min(z(~invalid));
    warndlg({[num2str(sum(invalid(:))) ' invalid (NaN) points in the file ' ...
        'were replaced by the minimal value of the image.'], ...
        'Avoid tracking objects in these areas.'}, 'Open Image', 'modal');
end

% Lateral and vertical scales, asking the user for those that the file does
% not provide (a text matrix exported without the informational header)
[width_nm, height_nm, zFactor_nm] = resolveScales(info);
if isempty(width_nm) % Cancel button pressed
    im = [];
    return
end

sizeX_nm = width_nm;
% One pixel side in nm (Gwyddion reports the full field size)
scaleXY = sizeX_nm/sizeX;

% FiberApp describes an image by a single lateral scale
scaleY = height_nm/sizeY;
if abs(scaleY - scaleXY) > 0.01*scaleXY
    warndlg({'The image has non-square pixels:', ...
        ['x: ' num2str(scaleXY) ' nm/pix, y: ' num2str(scaleY) ' nm/pix.'], ...
        'The x-scale is applied to both directions.'}, 'Open Image', 'modal');
    height_nm = scaleXY*sizeY;
end
sizeY_nm = height_nm;

% Height values in nm
z = z*zFactor_nm;

% Quantization step of the intensity units (nm per one intensity unit)
zRange = max(z(:)) - min(z(:));
if zRange > 0
    scaleZ = utility.round2n(zRange/N_LEVELS);
else % Flat image
    scaleZ = 1;
end

% Keep the integer intensity values within the exactly representable range
% of single precision, also for data with a large offset from zero
zSpan = max(abs(z(:)));
if scaleZ <= 0 || zSpan/scaleZ > 2^23
    scaleZ = utility.round2n(zSpan/2^23);
end

% Degenerate data (an empty or a numerically vanishing height range)
if ~isfinite(scaleZ) || scaleZ <= 0
    scaleZ = 1;
end

im = single(round(z/scaleZ));

% -------------------------------------------------------------------------
function [width_nm, height_nm, zFactor_nm] = resolveScales(info)
% Lateral size and value unit of the image, asked from the user if the file
% does not provide them. Empty output means that the user cancelled
width_nm = [];
height_nm = [];
zFactor_nm = [];

haveXY = isfinite(info.width_raw) && isfinite(info.xyFactor_nm);
haveZ = isfinite(info.zFactor_nm);

if haveXY
    width_nm = info.width_raw*info.xyFactor_nm;
    if isfinite(info.height_raw)
        height_nm = info.height_raw*info.xyFactor_nm;
    else % Square pixels
        height_nm = width_nm*info.sizeY/info.sizeX;
    end
end

if haveZ
    zFactor_nm = info.zFactor_nm;
end

if haveXY && haveZ
    return
end

% Suggested values, based on the magnitudes found in the file
if isfinite(info.width_raw)
    widthGuess = num2str(info.width_raw*utility.lengthUnitToNm(guessUnit(info.width_raw)));
else
    widthGuess = '';
end
zGuess = guessUnit(max(abs(info.z(isfinite(info.z)))));

prompt = {};
defaultAnswer = {};
if ~haveXY
    prompt{end+1} = 'Image width (nm):';
    defaultAnswer{end+1} = widthGuess;
end
if ~haveZ
    if isempty(info.zUnit)
        prompt{end+1} = 'Unit of the values (m, mm, um, nm, pm or A):';
    else
        prompt{end+1} = ['Unit of the values, "' info.zUnit ...
            '" is not a length (m, mm, um, nm, pm or A):'];
    end
    defaultAnswer{end+1} = zGuess;
end

while true
    answer = inputdlg(prompt, 'Gwyddion Text Import', 1, defaultAnswer);
    if isempty(answer) % Cancel button pressed
        width_nm = [];
        height_nm = [];
        zFactor_nm = [];
        return
    end
    defaultAnswer = answer;
    
    k = 0;
    valid = true;
    
    if ~haveXY
        k = k + 1;
        w = abs(real(str2double(answer{k})));
        if isempty(w) || ~isfinite(w) || w == 0
            errordlg('Image width must be a positive number.', 'Open Image');
            valid = false;
        else
            width_nm = w;
            height_nm = width_nm*info.sizeY/info.sizeX; % Square pixels
        end
    end
    
    if valid && ~haveZ
        k = k + 1;
        f = utility.lengthUnitToNm(answer{k});
        if isnan(f)
            errordlg('Unknown unit of the values.', 'Open Image');
            valid = false;
        else
            zFactor_nm = f;
        end
    end
    
    if valid
        return
    end
end

% -------------------------------------------------------------------------
function unit = guessUnit(value)
% Length unit that a bare number of this magnitude most likely has. Values
% exported by Gwyddion are in base SI units
if ~isempty(value) && isfinite(value) && value > 0 && value < 1e-3
    unit = 'm';
else
    unit = 'nm';
end
