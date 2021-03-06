function opt = j_t2star_smoothFreqMap(opt)
% =========================================================================
% 
% SMooth frequency map.
% 
% INPUT
% opt
%	opt.fname_multiecho_magn
%	opt.fname_multiecho_phase
%	opt.fname_freq
%	opt.fname_freq_smooth
%	opt.fname_freq_smooth_masked
%	opt.fname_mask
%	opt.echo_time						= (6.34:3.2:43); % in ms
% 	opt.thresh_mask						= 500; % intensity under which pixels are masked. Default=500.
% 	opt.rmse_thresh						= 2; % threshold above which voxels are discarded for comuting the frequency map. RMSE results from fitting the frequency slope on the phase data. Default=2.
% 
% OUTPUT
% opt
%
% Author: Julien Cohen-Adad <jcohen@nmr.mgh.harvard.edu>
% 2011-10-03: Created

% =========================================================================



% START FUNCTION
j_disp(opt.fname_log,['\n\n\n=========================================================================================================='])
j_disp(opt.fname_log,['   Running: j_t2star_smoothFreqMap'])
j_disp(opt.fname_log,['=========================================================================================================='])
j_disp(opt.fname_log,['.. Started: ',datestr(now),'\n'])



%% Load data

% Load frequency map
j_disp(opt.fname_log,['\nLoad frequency map...'])
fname = [opt.fname_freq];
j_disp(opt.fname_log,['.. File name: ',fname])
[img,dims,scales,bpp,endian] = read_avw(fname);
freq_3d = squeeze(img);
clear img
nx = size(freq_3d,1);
ny = size(freq_3d,2);
nz = size(freq_3d,3);
if opt.verbose, j_displayMRI(freq_3d,[-80 80]); title('Frequency map (Hz)'), end

% Downsample field map
j_disp(opt.fname_log,'Downsample field map...')
j_disp(opt.fname_log,['.. Downsampling factor: ',num2str(opt.smoothDownsampling)])
[x,y,z] = meshgrid(1:ny,1:nx,1:nz);
dx=opt.smoothDownsampling(1); dy=opt.smoothDownsampling(2); dz=opt.smoothDownsampling(3); 
[xi,yi,zi] = meshgrid(1:dy:ny,1:dx:nx,1:dz:nz);
freq_3d_i = interp3(x,y,z,freq_3d,xi,yi,zi,'nearest');
% j_displayMRI(freq_3d_i,[-80 80]);
nxi = size(freq_3d_i,1);
nyi = size(freq_3d_i,2);
nzi = size(freq_3d_i,3);
clear freq_3d
	

%% 3d smooth frequency map (zero values are ignored)
j_disp(opt.fname_log,['\n3d smooth frequency map using method: ',opt.smoothType,'...'])
j_disp(opt.fname_log,['----------'])
switch opt.smoothType
case 'gaussian'
	% Make kernel
	kernel = ones(opt.smoothKernel(1),opt.smoothKernel(2),opt.smoothKernel(3));
	j_disp(opt.fname_log,['.. Kernel size: ',num2str(opt.smoothKernel)])
	j_disp(opt.fname_log,['.. Kernel type: ',opt.smoothType])
	kernel_x = gausswin(opt.smoothKernel(1));
	kernel_x_3d = repmat(kernel_x,[1 opt.smoothKernel(2) opt.smoothKernel(3)]);
	kernel_y(1,:) = gausswin(opt.smoothKernel(2));
	kernel_y_3d = repmat(kernel_y,[opt.smoothKernel(1) 1 opt.smoothKernel(3)]);
	kernel_z(1,1,:) = gausswin(opt.smoothKernel(3));
	kernel_z_3d = repmat(kernel_z,[opt.smoothKernel(1) opt.smoothKernel(2) 1]);
	kernel = kernel_x_3d.*kernel_y_3d.*kernel_z_3d;
	% 3D convolution
	freq_3d_smooth = j_conv3(freq_3d,kernel,opt);
	
case 'box'
	% Make kernel
	kernel = ones(opt.smoothKernel(1),opt.smoothKernel(2),opt.smoothKernel(3));
	% 3D convolution
	freq_3d_smooth = j_conv3(freq_3d,kernel,opt);

case 'polyfit1d' % fit along Z

	% Calculate frequency gradient in the slice direction (freqGradZ)
	freq_3d_smooth = zeros(nx,ny,nz);
	icount=1;
	j_progress('\nFit frequency in Z direction...')
	for ix=1:nx
		for iy=1:ny
			% get frequency along z (discard zero values)
			freq_z = squeeze(freq_3d(ix,iy,:));
			ind_nonzero = find(freq_z);
			if length(ind_nonzero) >= opt.min_length
				% fit to polynomial function
				p = polyfit(ind_nonzero,freq_z(ind_nonzero),opt.polyFitOrder);
				f = polyval(p,(1:nz));
% 				% compute frequency gradient along Z
% 				grad_z = gradient(f,opt.dz/1000);		
	% figure, plot(freq_z(ind_nonzero),'o'), hold on, plot(f,'r'), plot(grad_z,'g')
				% fill 3D gradient matrix
				freq_3d_smooth(ix,iy,:) = f;
			end
			% display progress
			j_progress(icount/(nx*ny))
			icount=icount+1;
		end
	end

	
case 'polyfit3d'
	
	% re-build X,Y and Z indices
	j_disp(opt.fname_log,'Build new X,Y and Z indices...')
	[xi,yi,zi] = meshgrid(1:nyi,1:nxi,1:nzi);
	
	% find non-zero values
	j_disp(opt.fname_log,'Find non-zero values...')
	ind_nonzero = find(freq_3d_i(:));

	% build matrix of polynomial order
	j_disp(opt.fname_log,'Build matrix of polynomial orders...')
	model = [];
	icount = 1;
	for ipz=0:opt.smoothPolyOrder
		for ipy=0:opt.smoothPolyOrder
			for ipx=0:opt.smoothPolyOrder
				model(icount,:) = [ipx ipy ipz];
				icount = icount + 1;
			end
		end
	end
	nb_coeffs = icount - 1;
	j_disp(opt.fname_log,['.. Max. polynomial order: ',num2str(opt.smoothPolyOrder)])
	j_disp(opt.fname_log,['.. Number of coefficients: ',num2str(nb_coeffs)])
	
	% Run polynomial fit
	j_disp(opt.fname_log,['Run polynomial fit...'])
 	indepvar = [xi(ind_nonzero) yi(ind_nonzero) zi(ind_nonzero)];
	depvar = freq_3d_i(ind_nonzero);
	ifit = j_stat_polyfitn(indepvar,depvar,model);
	c = ifit.Coefficients;
	clear indepvar ind_nonzero depvar

	% Build series of unit polynomials
	j_disp(opt.fname_log,['Build series of unit polynomials...'])
	xi=xi(:)'; yi=yi(:)'; zi=zi(:)';
	matrix_poly = zeros(nb_coeffs,length(xi));
	for iOrder = 1:nb_coeffs
		matrix_poly(iOrder,:) = xi.^model(iOrder,1).*yi.^model(iOrder,2).*zi.^model(iOrder,3);
	end
	
	% reconstruct fitted image
	j_disp(opt.fname_log,['Reconstruct fitted volume...'])
	datafit = c*matrix_poly;
	freq_3d_smooth_i = reshape(datafit,nxi,nyi,nzi);
% j_displayMRI(datafit3d_i,[-80 80])
	clear matrix_poly
	
	% Build matrix of polynomial derivative along Z
	j_disp(opt.fname_log,['Build matrix of polynomial derivative along Z...'])
	matrix_poly_derivZ = zeros(nb_coeffs,length(xi));
	for iOrder = 1:nb_coeffs
		if model(iOrder,3)==0
			matrix_poly_derivZ(iOrder,:) = zeros(length(xi),1);
		else
			matrix_poly_derivZ(iOrder,:) = model(iOrder,3).*xi.^model(iOrder,1).*yi.^model(iOrder,2).*zi.^(model(iOrder,3)-1);
		end
	end
	
	% take the derivative along Z
	j_disp(opt.fname_log,['Compute derivative along Z...'])
	datafit_gradZ_i = c*matrix_poly_derivZ;
	freqGradZ_i = reshape(datafit_gradZ_i,nxi,nyi,nzi);
	clear datafit_gradZ_i matrix_poly_derivZ
	
end


% upsample data back to original resolution
j_disp(opt.fname_log,['Upsample data to native resolution (using nearest neighbor)...'])
[x,y,z] = meshgrid(1:ny,1:nx,1:nz);
[xi,yi,zi] = meshgrid(1:(ny-1)/(nyi-1):ny,1:(nx-1)/(nxi-1):nx,1:(nz-1)/(nzi-1):nz);
freq_3d_smooth = interp3(xi,yi,zi,freq_3d_smooth_i,x,y,z,'nearest');
freqGradZ = interp3(xi,yi,zi,freqGradZ_i,x,y,z,'nearest');
clear freqGradZ_i freq_3d_smooth_i


% Load mask
j_disp(opt.fname_log,['\nLoad mask...'])
fname = [opt.fname_mask];
j_disp(opt.fname_log,['.. File name: ',fname])
[img,dims,scales,bpp,endian] = read_avw(fname);
mask = squeeze(img);
clear img


% apply magnitude mask
j_disp(opt.fname_log,['Mask frequency and gradient map...'])
freq_3d_smooth_masked = freq_3d_smooth .* mask;
freqGradZ_masked = freqGradZ .* mask;
clear freq_3d_smooth freqGradZ mask
if opt.verbose, j_displayMRI(freq_3d_smooth_masked,[-80 80]); title('Smoothed frequency map (Hz)'), end
if opt.verbose, j_displayMRI(freqGradZ_masked,[-20 20]); title('GradientZ map (Hz/pix)'), end


% Save smoothed frequency map
j_disp(opt.fname_log,['\nSave smoothed frequency map...'])
j_disp(opt.fname_log,['.. output name: ',opt.fname_freq_smooth])
save_avw(freq_3d_smooth_masked,opt.fname_freq_smooth,'f',scales(1:3));
j_disp(opt.fname_log,['\nCopy geometric information from ',opt.fname_multiecho_magn,'...'])
cmd = [opt.fsloutput,'fslcpgeom ',opt.fname_multiecho_magn,' ',opt.fname_freq_smooth,' -d'];
j_disp(opt.fname_log,['>> ',cmd]); [status result] = unix(cmd); if status, error(result); end

% Save gradient map
j_disp(opt.fname_log,['\nSave gradient map...'])
j_disp(opt.fname_log,['.. output name: ',opt.fname_gradZ])
save_avw(freqGradZ_masked,opt.fname_gradZ,'f',scales(1:3));
j_disp(opt.fname_log,['\nCopy geometric information from ',opt.fname_multiecho_magn,'...'])
cmd = [opt.fsloutput,'fslcpgeom ',opt.fname_multiecho_magn,' ',opt.fname_gradZ,' -d'];
j_disp(opt.fname_log,['>> ',cmd]); [status result] = unix(cmd); if status, error(result); end


% % Save smooth masked frequency map
% j_disp(opt.fname_log,['Save smooth masked frequency map...'])
% j_disp(opt.fname_log,['.. output name: ',opt.fname_freq_smooth_masked])
% save_avw(freq_3d_smooth_masked,opt.fname_freq_smooth_masked,'f',scales(1:3));
% mask_ds = downsample3(mask,2);
% datafit3dm = datafit3d .* mask_ds;
% j_displayMRI(datafit3dm,[-80 80])
% 
% %% Save smooth frequency map
% j_disp(opt.fname_log,['Save smooth frequency map...'])
% j_disp(opt.fname_log,['.. output name: ',opt.fname_freq_smooth])
% save_avw(freq_3d_smooth,opt.fname_freq_smooth,'f',scales(1:3));
% j_disp(opt.fname_log,['\nCopy geometric information from ',opt.fname_multiecho_magn,'...'])
% cmd = [opt.fsloutput,'fslcpgeom ',opt.fname_multiecho_magn,' ',opt.fname_freq_smooth,' -d'];
% j_disp(opt.fname_log,['>> ',cmd]); [status result] = unix(cmd); if status, error(result); end




%% END FUNCTION
j_disp(opt.fname_log,['\n.. Ended: ',datestr(now)])
j_disp(opt.fname_log,['==========================================================================================================\n'])
