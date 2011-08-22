function bmask = pm_brain_mask(P,flags)
% Calculate a brain mask
% FORMAT bmask = pm_brain_mask(P,flags)
%
% P - is a single pointer to a single image
%
% flags - structure containing various options
%         template - which template for segmentation
%         fwhm     - fwhm of smoothing kernel for generating mask
%         nerode   - number of erosions
%         thresh   - threshold for smoothed mask 
%         ndilate  - number of dilations
%
%__________________________________________________________________________
%
% Inputs
% A single *.img conforming to SPM data format (see 'Data Format').
%
% Outputs
% Brain mask in a matrix
%__________________________________________________________________________
%
% The brain mask is generated by segmenting the image into GM, WM and CSF, 
% adding these components together then thresholding above zero.
% A morphological opening is performed to get rid of stuff left outside of
% the brain. Any leftover holes are filled. 
%
%__________________________________________________________________________
% @(#)pm_brain_mask.m	1.0 Chloe Hutton 05/02/26

if nargin < 2 | isempty(flags)
   %flags.template=fullfile(spm('Dir'),'templates','T1.nii');
   flags.fwhm=5;
   flags.nerode=1;
   flags.ndilate=2;
   flags.thresh=0.5;
   %flags.reg = 0.02;
   %flags.graphics=0;
end

disp('Segmenting and extracting brain...');
%seg_flags.estimate.reg=flags.reg;
%seg_flags.graphics = flags.graphics;
%VO=spm_segment(P.fname,flags.template,seg_flags);
%bmask=double(VO(1).dat)+double(VO(2).dat)+double(VO(3).dat)>0;
dat = pm_segment(P.fname);
bmask=double(dat(:,:,:,1))+double(dat(:,:,:,2))+double(dat(:,:,:,3))>0;
bmask=open_it(bmask,flags.nerode,flags.ndilate); % Do opening to get rid of scalp

% Calculate kernel in voxels:
vxs = sqrt(sum(P.mat(1:3,1:3).^2));
fwhm = repmat(flags.fwhm,1,3)./vxs;
bmask=fill_it(bmask,fwhm,flags.thresh); % Do fill to fill holes

OP=P;
brain_mask = [spm_str_manip(P.fname,'h') '/bmask',...
                spm_str_manip(P.fname,'t')];
OP.fname=brain_mask;
OP.descrip=sprintf('Mask:erode=%d,dilate=%d,fwhm=%d,thresh=%1.1f',flags.nerode,flags.ndilate,flags.fwhm,flags.thresh);
spm_write_vol(OP,bmask);

%__________________________________________________________________________

%__________________________________________________________________________
function ovol=open_it(vol,ne,nd)
% Do a morphological opening. This consists of an erosion, followed by 
% finding the largest connected component, followed by a dilation.

for i=1:ne
% Do an erosion then a connected components then a dilation 
% to get rid of stuff outside brain.

   evol=spm_erode(double(vol));
   evol=connect_it(evol);
   vol=spm_dilate(double(evol));
end

% Do some dilations to extend the mask outside the brain
for i=1:nd
   vol=spm_dilate(double(vol));
end

ovol=vol;

%__________________________________________________________________________

%__________________________________________________________________________
function ovol=fill_it(vol,k,thresh)
% Do morpholigical fill. This consists of finding the largest connected 
% component and assuming that is outside of the head. All the other 
% components are set to 1 (in the mask). The result is then smoothed by k
% and thresholded by thresh.
ovol=vol;

% Need to find connected components of negative volume
vol=~vol;
[vol,NUM]=ip_bwlabel(double(vol),26); 

% Now get biggest component and assume this is outside head..
pnc=0;
maxnc=1;
for i=1:NUM
   nc=size(find(vol==i),1);
   if nc>pnc
      maxnc=i;
      pnc=nc;
   end
end

% We know maxnc is largest cluster outside brain, so lets make all the
% others = 1.
for i=1:NUM
    if i~=maxnc
       nc=find(vol==i);
       ovol(nc)=1;
    end
end

spm_smooth(ovol,ovol,k);
ovol=ovol>thresh;

%_______________________________________________________________________

%_______________________________________________________________________
function ovol=connect_it(vol)
% Find connected components and return the largest one.

[vol,NUM]=ip_bwlabel(double(vol),26); 

% Get biggest component
pnc=0;
maxnc=1;
for i=1:NUM
   nc=size(find(vol==i),1);
   if nc>pnc
      maxnc=i;
      pnc=nc;
   end
end
ovol=(vol==maxnc);