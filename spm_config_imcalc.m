function opts = spm_config_imcalc
% Configuration file for image calculator
%_______________________________________________________________________
% Copyright (C) 2005 Wellcome Department of Imaging Neuroscience

% John Ashburner
% $Id: spm_config_imcalc.m 1032 2007-12-20 14:45:55Z john $

 
%_______________________________________________________________________
 

inpt.type = 'files';
inpt.name = 'Input Images';
inpt.tag  = 'input';
inpt.filter = 'image';
inpt.num  = [1 Inf];
inpt.help = {[...
'These are the images that are used by the calculator.  They ',...
'are referred to as i1, i2, i3, etc in the order that they are ',...
'specified.']};


outpt.type = 'entry';
outpt.name = 'Output Filename';
outpt.tag  = 'output';
outpt.strtype = 's';
outpt.num  = [1 Inf];
outpt.val  = {'output.img'};
outpt.help  = {[...
'The output image is written to current working directory ',...
'unless a valid full pathname is given. If a path name is given here, the ',...
    'output directory setting will be ignored.']};

outdir.type = 'files';
outdir.name = 'Output Directory';
outdir.tag  = 'outdir';
outdir.filter = 'dir';
outdir.num = [0 1];
outdir.val = {''};
outdir.help = {['Files produced by this function will be written into this ' ...
		'output directory. If no directory is given, images will be' ...
		' written to current working directory. If both output' ...
		' filename and output directory contain a directory, then '...
		'output filename takes precedence.']};

expr.type = 'entry';
expr.name = 'Expression';
expr.tag  = 'expression';
expr.strtype = 's';
expr.num  = [2 Inf];
expr.val = {'i1'};
expr.help = {...
'Example expressions (f):',...
'    * Mean of six images (select six images)',...
'       f = ''(i1+i2+i3+i4+i5+i6)/6''',...
'    * Make a binary mask image at threshold of 100',...
'       f = ''i1>100''',...
'    * Make a mask from one image and apply to another',...
'       f = ''i2.*(i1>100)''',[...
'             - here the first image is used to make the mask, which is applied to the second image'],...
'    * Sum of n images',...
'       f = ''i1 + i2 + i3 + i4 + i5 + ...''',...
'    * Sum of n images (when reading data into a data-matrix - use dmtx arg)',...
'       f = ''sum(X)'''};
 
dmtx.type = 'menu';
dmtx.name = 'Data Matrix';
dmtx.tag  = 'dmtx';
dmtx.labels = {'No - don''t read images into data matrix','Yes -  read images into data matrix'};
dmtx.values = {0,1};
dmtx.def  = 'imcalc.dmtx';
%dmtx.val = {0};
dmtx.help = {[...
'If the dmtx flag is set, then images are read into a data matrix X ',...
'(rather than into separate variables i1, i2, i3,...). The data matrix ',...
' should be referred to as X, and contains images in rows. ',...
'Computation is plane by plane, so in data-matrix mode, X is a NxK ',...
'matrix, where N is the number of input images [prod(size(Vi))], and K ',...
'is the number of voxels per plane [prod(Vi(1).dim(1:2))].']};

mask.type = 'menu';
mask.name = 'Masking';
mask.tag  = 'mask';
mask.labels = {'No implicit zero mask','Implicit zero mask','NaNs should be zeroed'};
mask.values = {0,1,-1};
mask.def  = 'imcalc.mask';
%mask.val = {0};
mask.help = {[...
'For data types without a representation of NaN, implicit zero masking ',...
'assumes that all zero voxels are to be treated as missing, and ',...
'treats them as NaN. NaN''s are written as zero (by spm_write_plane), ',...
'for data types without a representation of NaN.']};

intrp.type = 'menu';
intrp.name = 'Interpolation';
intrp.tag  = 'interp';
intrp.labels = {'Nearest neighbour','Trilinear','2nd Degree Sinc',...
'3rd Degree Sinc','4th Degree Sinc','5th Degree Sinc',...
'6th Degree Sinc','7th Degree Sinc'};
intrp.values = {0,1,-2,-3,-4,-5,-6,-7};
intrp.def    = 'imcalc.interp';
%intrp.val   = {1};
h1 = [...
'With images of different sizes and orientations, the size and ',...
'orientation of the first is used for the output image. A warning is ',...
'given in this situation. Images are sampled into this orientation ',...
'using the interpolation specified by the hold parameter.'];
intrp.help    = {h1,'',[...
'The method by which the images are sampled when being written in a ',...
'different space.'],...
'    Nearest Neighbour',...
'    - Fastest, but not normally recommended.',...
'    Bilinear Interpolation',...
'    - OK for PET, or realigned fMRI.',...
'    Sinc Interpolation',...
'    - Better quality (but slower) interpolation, especially',...
'      with higher degrees.'...
};

dtype.type = 'menu';
dtype.name = 'Data Type';
dtype.tag  = 'dtype';
dtype.labels = {'UINT8  - unsigned char','INT16 - signed short','INT32 - signed int','FLOAT - single prec. float','DOUBLE - double prec. float'};
dtype.values = {spm_type('uint8'),spm_type('int16'),spm_type('int32'),spm_type('float32'),spm_type('float64')};
dtype.def  = 'imcalc.dtype';
%dtype.val = {spm_type('int16')};
dtype.help = {'Data-type of output image'};

options.type = 'branch';
options.name = 'Options';
options.tag  = 'options';
options.val  = {dmtx,mask,intrp,dtype};
options.help = {'Options for image calculator'};

opts.type = 'branch';
opts.name = 'Image Calculator';
opts.tag  = 'imcalc';
opts.val  = {inpt,outpt,outdir,expr,options};
opts.prog = @fun;
opts.vfiles = @vfiles;
opts.help = {[...
'The image calculator is for performing user-specified ',...
'algebraic manipulations on a set of images, with the result being ',...
'written out as an image. The user is prompted to supply images to ',...
'work on, a filename for the output image, and the expression to ',...
'evaluate. The expression should be a standard MATLAB expression, ',...
'within which the images should be referred to as i1, i2, i3,... etc.']};
return;

function fun(opt)
flags = {opt.options.dmtx, opt.options.mask, opt.options.dtype, opt.options.interp};
outfile = vfiles(opt);
spm_imcalc_ui(strvcat(opt.input{:}),outfile{1},opt.expression,flags);
return;

function vf = vfiles(job)
[p,nam,ext,num] = spm_fileparts(job.output);
if isempty(p)
    if isempty(job.outdir{1})
	p=pwd;
    else
	p = job.outdir{1};
    end;
end;
if isempty(strfind(ext,','))
    ext=[ext ',1'];
end;
vf{1} = fullfile(p,[nam ext num]);
return;

