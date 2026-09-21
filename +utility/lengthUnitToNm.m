%LENGTHUNITTONM Number of nanometers in one given length unit
%
%   f = utility.lengthUnitToNm(unit)
%
%   Returns NaN for an empty, unknown or non-length unit. SI prefixes from
%   pico to kilo are recognized, as well as the angstrom. The micro and the
%   angstrom signs are accepted both as single characters (U+00B5, U+03BC,
%   U+00C5, U+00E5, U+212B) and as the byte pairs that appear when a UTF-8
%   file is read as 8-bit characters, since files exported by Gwyddion are
%   UTF-8 encoded.

% Copyright (c) 2011-2014 ETH Zurich, 2015 FiberApp Contributors. All rights reserved.
% Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

function f = lengthUnitToNm(unit)
f = NaN;
if ~ischar(unit)
    return
end

unit = strtrim(unit);
if isempty(unit)
    return
end

c = double(unit);
isMicro = any(c == 181 | c == 956) || ...
    (numel(c) > 1 && ((c(1) == 194 && c(2) == 181) || (c(1) == 206 && c(2) == 188)));
isAngstrom = any(c == 197 | c == 229 | c == 8491) || ...
    (numel(c) > 1 && c(1) == 195 && (c(2) == 133 || c(2) == 165));

% Non-ascii characters are dropped, the remainder identifies the unit
ascii = unit(c < 128);

if isMicro && (isempty(ascii) || strcmpi(ascii, 'm'))
    f = 1e3;
    return
end

if isAngstrom && (isempty(ascii) || strcmpi(ascii, 'a'))
    f = 0.1;
    return
end

switch lower(ascii)
    case 'km'
        f = 1e12;
    case 'm'
        f = 1e9;
    case 'dm'
        f = 1e8;
    case 'cm'
        f = 1e7;
    case 'mm'
        f = 1e6;
    case {'um', 'mum', 'mcm'}
        f = 1e3;
    case 'nm'
        f = 1;
    case 'pm'
        f = 1e-3;
    case {'a', 'ang', 'angstrom'}
        f = 0.1;
end
