%PARSEGWYDDIONTEXT Parse a Gwyddion ASCII (*.txt) export of an SPM channel
%
%   info = utility.parseGwyddionText(fullName)
%
%   Reads a text file written by Gwyddion ("Export Text Data", plain text
%   matrix, with or without the informational header) or a three-column
%   XYZ text file sampled on a regular grid. The function performs no
%   graphical output, so that it can be tested and reused independently of
%   the FiberApp GUI; all dialogs are handled by utility.readGwyddionImage.
%
%   The returned structure contains the following fields:
%       ok          - true if a numeric data array was recovered
%       message     - reason of the failure, empty if ok
%       format      - 'matrix' or 'xyz'
%       z           - raw data matrix, in the units of the file (double).
%                     Row 1 corresponds to the first data row of the file,
%                     i.e. to the top of the image as displayed in Gwyddion
%       sizeX       - number of columns (pixels)
%       sizeY       - number of rows (pixels)
%       width_raw   - lateral field width, in the units of the file, or NaN
%       height_raw  - lateral field height, in the units of the file, or NaN
%       xyFactor_nm - nm per one lateral unit, or NaN if the unit is unknown
%       zFactor_nm  - nm per one value unit, or NaN if the unit is unknown
%       xyUnit      - lateral unit as written in the file
%       zUnit       - value unit as written in the file
%       channel     - channel title, empty if not present in the file
%       header      - cell array of the comment lines of the file
%
%   Lateral sizes reported by Gwyddion are full field sizes, i.e.
%   width_raw = sizeX*dx, where dx is the pixel size.

% Copyright (c) 2011-2014 ETH Zurich, 2015 FiberApp Contributors. All rights reserved.
% Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

function info = parseGwyddionText(fullName)
info = struct('ok', false, 'message', '', 'format', '', 'z', [], ...
    'sizeX', [], 'sizeY', [], 'width_raw', NaN, 'height_raw', NaN, ...
    'xyFactor_nm', NaN, 'zFactor_nm', NaN, 'xyUnit', '', 'zUnit', '', ...
    'channel', '', 'header', {{}});

if exist(fullName, 'file') ~= 2
    info.message = 'File not found.';
    return
end

fid = fopen(fullName, 'r');
if fid == -1
    info.message = 'File cannot be opened for reading.';
    return
end

% Read the file header (comment lines and any other non-numeric lines) up
% to the first line that contains numbers
header = {};
firstLine = '';
while true
    ln = fgetl(fid);
    if ~ischar(ln) % end of file
        break
    end
    
    s = strtrim(ln);
    if isempty(s)
        continue
    end
    
    if s(1) == '#' || s(1) == '%'
        header{end+1} = s; %#ok<AGROW>
        continue
    end
    
    % A data line is a line that starts with a number
    if isempty(sscanf(cleanSeparators(s), '%f', 1))
        header{end+1} = s; %#ok<AGROW>
        continue
    end
    
    firstLine = s;
    break
end
info.header = header;

if isempty(firstLine)
    fclose(fid);
    info.message = 'Selected file does not contain any numeric data.';
    return
end

% Number of columns is defined by the first data line
firstRow = sscanf(cleanSeparators(firstLine), '%f');
nCols = numel(firstRow);

% Read the remaining values. Files exported by Gwyddion are whitespace
% separated, which fscanf handles directly and without an extra copy of the
% (potentially very large) file in memory. Other separators are substituted
% before parsing
if isSeparated(firstLine)
    rest = cleanSeparators(fread(fid, inf, '*char')');
    fclose(fid);
    [values, ~, ~, nextIdx] = sscanf(rest, '%f');
    tail = rest(min(nextIdx, numel(rest)+1):end);
    clear rest
else
    values = fscanf(fid, '%f');
    % Everything that fscanf could not interpret as a number
    tail = fread(fid, inf, '*char')';
    fclose(fid);
end

% Numeric parsing stops at the first character that is not a number, so an
% unreadable file would otherwise be silently truncated
[isTrailing, snippet] = hasTrailingContent(tail);
if isTrailing
    info.message = ['The file contains non-numeric data after the numeric ' ...
        'block, near: "' snippet '".'];
    return
end

values = [firstRow; values];
if mod(numel(values), nCols) ~= 0
    info.message = ['Inconsistent number of values in the file: the data ' ...
        'cannot be interpreted as a rectangular array.'];
    return
end
nRows = numel(values)/nCols;

% Values are read along the lines of the file, thus the transposition
data = reshape(values, nCols, nRows)';
clear values

% Informational header of Gwyddion
[channel, width, widthUnit, height, heightUnit, valueUnit] = parseHeader(header);
info.channel = channel;

if nCols == 3 && nRows > 9 && isempty(width)
    % Three columns of a plain XYZ export. The lateral sizes of such files
    % are taken from the coordinates themselves, hence the check that the
    % header did not provide them (a genuine three-pixel-wide matrix)
    [zGrid, dx, dy] = gridXYZ(data);
    if ~isempty(zGrid)
        info.format = 'xyz';
        info.z = zGrid;
        [info.sizeY, info.sizeX] = size(zGrid);
        info.width_raw = dx*info.sizeX;
        info.height_raw = dy*info.sizeY;
        % Plain XYZ files carry no units; those of the value column are
        % resolved by the caller
        info.xyUnit = '';
        info.zUnit = valueUnit;
        info.xyFactor_nm = NaN;
        info.zFactor_nm = utility.lengthUnitToNm(valueUnit);
        info.ok = true;
        return
    end
end

% Plain matrix of values
info.format = 'matrix';
info.z = data;
[info.sizeY, info.sizeX] = size(data);

if info.sizeX < 2 || info.sizeY < 2
    info.ok = false;
    info.message = 'The data array is too small to be an image.';
    return
end

if ~isempty(width)
    info.width_raw = width;
    info.xyUnit = widthUnit;
    info.xyFactor_nm = utility.lengthUnitToNm(widthUnit);
end
if ~isempty(height)
    info.height_raw = height;
    if isempty(width)
        info.xyUnit = heightUnit;
        info.xyFactor_nm = utility.lengthUnitToNm(heightUnit);
    elseif ~strcmp(heightUnit, widthUnit)
        % Mixed lateral units, convert the height to the width unit
        fh = utility.lengthUnitToNm(heightUnit);
        fw = utility.lengthUnitToNm(widthUnit);
        if ~isnan(fh) && ~isnan(fw) && fw ~= 0
            info.height_raw = height*fh/fw;
        end
    end
end

info.zUnit = valueUnit;
info.zFactor_nm = utility.lengthUnitToNm(valueUnit);
info.ok = true;

% -------------------------------------------------------------------------
function [tf, snippet] = hasTrailingContent(str)
% True if the remainder of the file holds anything but blanks and comments
tf = false;
snippet = '';
if isempty(str)
    return
end

lines = regexp(str, '[\r\n]+', 'split');
for k = 1:length(lines)
    s = strtrim(lines{k});
    if isempty(s) || s(1) == '#' || s(1) == '%'
        continue
    end
    tf = true;
    snippet = s(1:min(40, length(s)));
    return
end

% -------------------------------------------------------------------------
function tf = isSeparated(str)
% True if the line uses separators other than whitespace
tf = any(str == ',' | str == ';');

% -------------------------------------------------------------------------
function str = cleanSeparators(str)
% Replace non-whitespace separators by blanks
str(str == ',' | str == ';') = ' ';

% -------------------------------------------------------------------------
function [channel, width, widthUnit, height, heightUnit, valueUnit] = parseHeader(header)
% Extract the fields of the informational header of Gwyddion
channel = '';
width = [];
widthUnit = '';
height = [];
heightUnit = '';
valueUnit = '';

for k = 1:length(header)
    ln = header{k};
    % Strip the comment characters
    ln = strtrim(ln(cumsum(ln ~= '#' & ln ~= '%' & ln ~= ' ') > 0));
    
    idx = find(ln == ':', 1, 'first');
    if isempty(idx)
        continue
    end
    key = strtrim(ln(1:idx-1));
    val = strtrim(ln(idx+1:end));
    if isempty(val)
        continue
    end
    
    if ~isempty(regexpi(key, '^channel', 'once'))
        channel = val;
    elseif ~isempty(regexpi(key, '^width', 'once'))
        [width, widthUnit] = splitValueUnit(val);
    elseif ~isempty(regexpi(key, '^height', 'once'))
        [height, heightUnit] = splitValueUnit(val);
    elseif ~isempty(regexpi(key, '^value\s*units?', 'once'))
        valueUnit = val;
    elseif ~isempty(regexpi(key, '^(x|y)\s*units?', 'once'))
        if isempty(widthUnit)
            widthUnit = val;
        end
        if isempty(heightUnit)
            heightUnit = val;
        end
    elseif ~isempty(regexpi(key, '^(z)\s*units?', 'once'))
        valueUnit = val;
    end
end

% -------------------------------------------------------------------------
function [val, unit] = splitValueUnit(str)
% Split a "5.000 um" like string into the number and the unit
val = [];
unit = '';
[v, cnt, ~, nextIdx] = sscanf(str, '%f', 1);
if cnt ~= 1
    return
end
val = v;
unit = strtrim(str(nextIdx:end));

% -------------------------------------------------------------------------
function [zGrid, dx, dy] = gridXYZ(data)
% Convert three columns of x, y and z values into a matrix, provided that
% the points form a complete regular grid
zGrid = [];
dx = [];
dy = [];

x = data(:,1);
y = data(:,2);
z = data(:,3);

ux = unique(x);
uy = unique(y);
nx = numel(ux);
ny = numel(uy);

if nx < 2 || ny < 2 || nx*ny ~= numel(z)
    return
end

% Regular spacing along both axes (within a 1% tolerance, the coordinates
% are written with a limited number of digits)
ddx = diff(ux);
ddy = diff(uy);
dx = mean(ddx);
dy = mean(ddy);
if any(abs(ddx - dx) > 0.01*dx) || any(abs(ddy - dy) > 0.01*dy)
    zGrid = [];
    return
end

[~, ix] = ismember(x, ux);
[~, iy] = ismember(y, uy);
ind = sub2ind([ny nx], iy, ix);

% Every node of the grid has to be covered exactly once
if numel(unique(ind)) ~= numel(ind)
    zGrid = [];
    return
end

zGrid = NaN(ny, nx);
zGrid(ind) = z;
