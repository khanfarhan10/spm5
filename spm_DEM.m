function [DEM] = spm_DEM(DEM)
% Dynamic expectation maxmisation
% FORMAT DEM   = spm_DEM(DEM)
%
% DEM.M  - hierarchical model
% DEM.Y  - response varaible, output or data
% DEM.U  - explanatory variables, inputs or prior expectation of causes
% DEM.X  - confounds
%__________________________________________________________________________
%
% generative model
%--------------------------------------------------------------------------
%   M(i).g  = y(t)  = g(x,v,P)    {inline function, string or m-file}
%   M(i).f  = dx/dt = f(x,v,P)    {inline function, string or m-file}
%
%   M(i).pE = prior expectation of p model-parameters
%   M(i).pC = prior covariances of p model-parameters
%   M(i).hE = prior expectation of h hyper-parameters (cause noise)
%   M(i).hC = prior covariances of h hyper-parameters (cause noise)
%   M(i).gE = prior expectation of g hyper-parameters (state noise)
%   M(i).gC = prior covariances of g hyper-parameters (state noise)
%   M(i).Q  = precision components (input noise)
%   M(i).R  = precision components (state noise)
%   M(i).V  = fixed precision (input noise)
%   M(i).W  = fixed precision (state noise)
%
%   M(i).m  = number of inputs v(i + 1);
%   M(i).n  = number of states x(i);
%   M(i).l  = number of output v(i);
%
% conditional moments of model-states - q(u)
%--------------------------------------------------------------------------
%   qU.x    = Conditional expectation of hidden states
%   qU.v    = Conditional expectation of causal states
%   qU.z    = Conditional prediction error (causes)
%   qU.C    = Conditional covariance: cov(v)
%   qU.S    = Conditional covariance: cov(x)
%
% conditional moments of model-parameters - q(p)
%--------------------------------------------------------------------------
%   qP.P    = Conditional expectation
%   qP.C    = Conditional covariance
%  
% conditional moments of hyper-parameters (log-transformed) - q(h)
%--------------------------------------------------------------------------
%   qH.h    = Conditional expectation (cause noise)
%   qH.g    = Conditional expectation (state noise)
%   qH.C    = Conditional covariance
%
% F         = log evidence = log marginal likelihood = negative free energy
%__________________________________________________________________________
%
% spm_DEM implements a variational Bayes (VB) scheme under the Laplace
% approximation to the conditional densities of states (u), parameters (p)
% and hyperparameters (h) of any analytic nonlinear hierarchical dynamic
% model, with additive Gaussian innovations.  It comprises three
% variational steps (D,E and M) that update the conditional moments of u, p
% and h respectively
%
%                D: qu.u = max <L>q(p,h)
%                E: qp.p = max <L>q(u,h)
%                M: qh.h = max <L>q(u,p)
%
% where qu.u corresponds to the conditional expectation of hidden states x 
% and causal states v and so on.  L is the ln p(y,u,p,h|M) under the model 
% M. The conditional covariances obtain analytically from the curvature of 
% L with respect to u, p and h.
%
% The D-step is embedded in the E-step because q(u) changes with each
% sequential observation.  The dynamical model is transformed into a static
% model using temporal derivatives at each time point.  Continuity of the
% conditional trajectories q(u,t) is assured by a continuous ascent of F(t)
% in generalised co-ordinates.  This means DEM can deconvolve online and can
% represents an alternative to Kalman filtering or alternative Bayesian 
% update procedures.
%
%==========================================================================
% Copyright (C) 2005 Wellcome Department of Imaging Neuroscience

% Karl Friston
% $Id$

% check model, data, priors and confounds and unpack
%--------------------------------------------------------------------------
[M Y U X] = spm_DEM_set(DEM);

% find or create a DEM figure
%--------------------------------------------------------------------------
clear spm_DEM_eval
sw = warning('off');
Fdem     = spm_figure('GetWin','DEM');

% tolerance for changes in norm
%--------------------------------------------------------------------------
TOL  = 1e-3;

% order parameters (d = n = 1 for static models) and checks
%==========================================================================
d    = M(1).E.d + 1;                   % embedding order of q(v)
n    = M(1).E.n + 1;                   % embedding order of q(x) (n >= d)
s    = M(1).E.s;                       % smoothness - s.d. of kernel (bins)

% number of states and parameters
%--------------------------------------------------------------------------
nY   = size(Y,2);                      % number of samples
nl   = size(M,2);                      % number of levels
nv   = sum(spm_vec(M.m));              % number of v (casual states)
nx   = sum(spm_vec(M.n));              % number of x (hidden states)
ny   = M(1).l;                         % number of y (inputs)
nc   = M(end).l;                       % number of c (prior causes)
nu   = nv*d + nx*n;                    % number of generalised states

% number of iterations
%--------------------------------------------------------------------------
try nD = M(1).E.nD; catch nD = 1;  end
try nE = M(1).E.nE; catch nE = 1;  end
try nM = M(1).E.nM; catch nM = 8;  end
try nN = M(1).E.nN; catch nN = 16; end

% initialise regularisation parameters
%--------------------------------------------------------------------------
if nx
    td = 1/nD;                            % integration time for D-Step
    te = exp(32);                          % integration time for E-Step
else
    td = {64};
    te = exp(32);
end

% precision (R) and covariance of generalised errors
%--------------------------------------------------------------------------
iV    = spm_DEM_R(n,s);

% precision components Q{} requiring [Re]ML estimators (M-Step)
%==========================================================================
Q     = {};
for i = 1:nl
    q0{i,i} = sparse(M(i).l,M(i).l);
    r0{i,i} = sparse(M(i).n,M(i).n);
end
Q0    = kron(iV,spm_cat(q0));
R0    = kron(iV,spm_cat(r0));
for i = 1:nl
    for j = 1:length(M(i).Q)
        q          = q0;
        q{i,i}     = M(i).Q{j};
        Q{end + 1} = blkdiag(kron(iV,spm_cat(q)),R0);
    end
    for j = 1:length(M(i).R)
        q          = r0;
        q{i,i}     = M(i).R{j};
        Q{end + 1} = blkdiag(Q0,kron(iV,spm_cat(q)));
    end
end


% and fixed components P
%--------------------------------------------------------------------------
Q0    = kron(iV,spm_cat(diag({M.V})));
R0    = kron(iV,spm_cat(diag({M.W})));
Qp    = blkdiag(Q0,R0);
Q0    = kron(iV,speye(nv));
R0    = kron(iV,speye(nx));
Qu    = blkdiag(Q0,R0);
nh    = length(Q);                         % number of hyperparameters

% fixed priors on states (u)
%--------------------------------------------------------------------------
Px    = kron(iV(1:n,1:n),sparse(nx,nx));
Pv    = kron(iV(1:d,1:d),sparse(nv,nv));
Pu    = spm_cat(diag({Px Pv}));

% hyperpriors
%--------------------------------------------------------------------------
ph.h  = spm_vec({M.hE M.gE});              % prior expectation of h
ph.c  = spm_cat(diag({M.hC M.gC}));        % prior covariances of h
qh.h  = ph.h;                              % conditional expectation
qh.c  = ph.c;                              % conditional covariance
ph.ic = inv(ph.c);                         % prior precision 

% priors on parameters (in reduced parameter space)
%==========================================================================
pp.c  = cell(nl,nl);
qp.p  = cell(nl,1);
for i = 1:(nl - 1)
 
    % eigenvector reduction: p <- pE + qp.u*qp.p
    %----------------------------------------------------------------------
    qp.u{i}   = spm_svd(M(i).pC);                    % basis for parameters
    M(i).p    = size(qp.u{i},2);                     % number of qp.p
    qp.p{i}   = sparse(M(i).p,1);                    % initial qp.p
    pp.c{i,i} = qp.u{i}'*M(i).pC*qp.u{i};            % prior covariance

end
Up    = spm_cat(diag(qp.u));
 
% initialise and augment with confound parameters B; with flat priors
%--------------------------------------------------------------------------
np    = sum(spm_vec(M.p));                  % number of model parameters
nb    = size(X,1);                          % number of confounds
nn    = nb*ny;                              % number of nuisance parameters
nf    = np + nn;                            % numer of free parameters
ip    = [1:np];
ib    = [1:nn] + np;
pp.c  = spm_cat(pp.c);
pp.ic = inv(pp.c);
 
% initialise conditional density q(p) (for D-Step)
%--------------------------------------------------------------------------
qp.e  = spm_vec(qp.p);
qp.c  = sparse(nf,nf);
qp.b  = sparse(ny,nb);

% initialise dedb
%--------------------------------------------------------------------------
for i = 1:nl
    dedbi{i,1} = sparse(M(i).l,nn);
end
for i = 1:nl - 1
    dndbi{i,1} = sparse(M(i).n,nn);
end
for i = 1:n
    dEdb{i,1}  = spm_cat(dedbi);
end
for i = 1:n
    dNdb{i,1}  = spm_cat(dndbi);
end
dEdb  = [dEdb; dNdb];


% initialise cell arrays for D-Step; e{i + 1} = (d/dt)^i[e] = e[i]
%==========================================================================
qu.x      = cell(n,1);
qu.v      = cell(n,1);
qu.y      = cell(n,1);
qu.u      = cell(n,1);
[qu.x{:}] = deal(sparse(nx,1));
[qu.v{:}] = deal(sparse(nv,1));
[qu.y{:}] = deal(sparse(ny,1));
[qu.u{:}] = deal(sparse(nc,1));
 
% initialise cell arrays for hierarchical structure of x[0] and v[0]
%--------------------------------------------------------------------------
x         = {M(1:end - 1).x};
v         = {M(1 + 1:end).v};
qu.x{1}   = spm_vec(x);
qu.v{1}   = spm_vec(v);

% derivatives for Jacobian of D-step
%--------------------------------------------------------------------------
Dx    = kron(spm_speye(n,n,1),spm_speye(nx,nx,0));
Dv    = kron(spm_speye(d,d,1),spm_speye(nv,nv,0));
Dy    = kron(spm_speye(n,n,1),spm_speye(ny,ny,0));
Dc    = kron(spm_speye(d,d,1),spm_speye(nc,nc,0));
D     = spm_cat(diag({Dx,Dv,Dy,Dc}));
              
% and null blocks
%--------------------------------------------------------------------------
dVdy  = sparse(n*ny,1);
dVdc  = sparse(d*nc,1);              
dVdyy = sparse(n*ny,n*ny);
dVdcc = sparse(d*nc,d*nc);

% gradients and curvatures for conditional uncertainty
%--------------------------------------------------------------------------
dWdu  = sparse(nu,1);
dWdp  = sparse(nf,1);
dWduu = sparse(nu,nu);
dWdpp = sparse(nf,nf);

% preclude unneceassry iterations
%--------------------------------------------------------------------------
if ~nh,        nM = 1; end
if ~nf,        nE = 1; end
if ~nf && ~nh, nN = 1; end


% Iterate DEM
%==========================================================================
Fm     = -exp(64);
for iN = 1:nN
 
    % E-Step: (with embedded D-Step)
    %======================================================================
    mp     = 0;                                % cumulator for changes in p
    Fe     = -exp(64);                         % Free energy (E-stpep)
    for iE = 1:nE
 

        % [re-]set accumulators for E-Step
        %------------------------------------------------------------------
        dFdp  = zeros(nf,1);
        dFdpp = zeros(nf,nf);
        EE    = sparse(0);
        ECE   = sparse(0);
        qp.ic = sparse(0);
        qu_c  = speye(1);
        
        
        % [re-]set precisions using ReML hyperparameter estimates
        %------------------------------------------------------------------
        iS    = Qp;
        for i = 1:nh
           iS = iS + Q{i}*exp(qh.h(i));
        end
        
        % [re-]adjust for confounds
        %------------------------------------------------------------------
        Y     = Y - qp.b*X;
        
        % [re-]set states & their derivatives
        %------------------------------------------------------------------
        try
            qu = qU(1);
        end
        
        % D-Step: (nD D-Steps for each sample)
        %==================================================================
        for iY = 1:nY

            % [re-]set states for static systems
            %--------------------------------------------------------------
            if ~nx
                try, qu = qU(iY); end
            end

            % D-Step: until convergence for static systems
            %==============================================================
            Fd     = -exp(64);
            for iD = 1:nD
                
                % sampling time
                %----------------------------------------------------------
                ts        = iY + (iD - 1)/nD;
                
                % derivatives of responses and inputs
                %----------------------------------------------------------
                qu.y(1:n) = spm_DEM_embed(Y,n,ts);
                qu.u(1:d) = spm_DEM_embed(U,d,ts);

                % compute dEdb (derivatives of confounds)
                %----------------------------------------------------------
                b     = spm_DEM_embed(X,n,ts);
                for i = 1:n
                    dedbi{1}  = -kron(b{i}',speye(ny,ny));
                    dEdb{i,1} =  spm_cat(dedbi);
                end

                % evaluate functions:
                % E = v - g(x,v) and derivatives dE.dx, ...
                %==========================================================       
                [E dE] = spm_DEM_eval(M,qu,qp);
                
                % conditional covariance [of states {u}]
                %----------------------------------------------------------
                qu.c   = inv(dE.du'*iS*dE.du + Pu);
                qu_c   = qu_c*qu.c;
                
                % and conditional covariance [of parameters {P}]
                %----------------------------------------------------------
                dE.dP  = [dE.dp spm_cat(dEdb)];
                ECEu   = dE.du*qu.c*dE.du';
                ECEp   = dE.dP*qp.c*dE.dP';
                
                % Evaluate objective function L(t) (for static models)
                %----------------------------------------------------------
                if ~nx
                    
                    L = - trace(E'*iS*E)/2 ...           % states (u)
                        - trace(iS*ECEp)/2;              % expectation q(p)

                    % if F is increasing, save expansion point
                    %------------------------------------------------------
                    if L > Fd
                        td     = {min(td{1}*2,256)};
                        Fd     = L;
                        B.qu   = qu;
                        B.E    = E;
                        B.dE   = dE;
                        B.ECEp = ECEp;
                    else
                        % otherwise, return to previous expansion point
                        %--------------------------------------------------
                        qu     = B.qu;
                        E      = B.E;
                        dE     = B.dE;
                        ECEp   = B.ECEp;
                        td     = {min(td{1}/2,16)};
                    end
                end

                % save states at qu(t)
                %----------------------------------------------------------
                if iD == 1
                    qE{iY} = E;
                    qU(iY) = qu;
                end
                
                
                % uncertainty about parameters dWdv, ... ; W = ln(|qp.c|)
                %==========================================================
                if np
                    for i = 1:nu
                        CJp(:,i)   = spm_vec(qp.c(ip,ip)*dE.dpu{i}'*iS);
                        dEdpu(:,i) = spm_vec(dE.dpu{i}');
                    end
                    dWdu   = CJp'*spm_vec(dE.dp');
                    dWduu  = CJp'*dEdpu;
                end


                % D-step update: of causes v{i}, and hidden states x(i)
                %==========================================================
                
                % conditional modes
                %----------------------------------------------------------
                q     = {qu.x{1:n} qu.v{1:d} qu.y{1:n} qu.u{1:d}};
                u     = spm_vec(q);
                
                % first-order derivatives
                %----------------------------------------------------------             
                dVdu  = -dE.du'*iS*E     - dWdu/2  - Pu*u(1:nu); 
                
                % and second-order derivatives
                %----------------------------------------------------------
                dVduu = -dE.du'*iS*dE.du - dWduu/2 - Pu;
                dVduy = -dE.du'*iS*dE.dy;
                dVduc = -dE.du'*iS*dE.dc;
                
                % gradient
                %----------------------------------------------------------
                dFdu  = spm_vec({dVdu;  dVdy;  dVdc });         
                                 
                % Jacobian (variational flow)
                %----------------------------------------------------------
                dFduu = spm_cat({dVduu  dVduy  dVduc  ;
                                 []     dVdyy  []     ;
                                 []     []     dVdcc});
                
                
                % update conditional modes of states
                %==========================================================
                du    = spm_dx(dFduu + D,dFdu + D*u,td);                
                q     = spm_unvec(u + du,q);
                
                % and save them
                %----------------------------------------------------------
                qu.x(1:n) = q([1:n]);
                qu.v(1:d) = q([1:d] + n);
                
        
                % D-Step: break if convergence (for static models)
                %----------------------------------------------------------
                if ~nx
                    qU(iY) = qu; 
                end
                if ~nx && ((dFdu'*du < 1e-2) || (norm(du,1) < TOL))
                    break
                end
                if ~nx && nY < 8
                    % report (D-Steps)
                    %------------------------------------------------------
                    str{1} = sprintf('D-Step: %i (%i)',iD,iY);
                    str{2} = sprintf('I:%.6e',full(Fd));
                    str{3} = sprintf('u:%.2e',full(du'*du));
                    fprintf('%-16s%-24s%-16s\n',str{1:3})
                end

            end % D-Step
            
            % Gradients and curvatures for E-Step: W = tr(C*J'*iS*J)
            %==============================================================
            if np
                for i = ip
                    CJu(:,i)   = spm_vec(qu.c*dE.dup{i}'*iS);
                    dEdup(:,i) = spm_vec(dE.dup{i}');
                end
                dWdp(ip)       = CJu'*spm_vec(dE.du');
                dWdpp(ip,ip)   = CJu'*dEdup;
            end

 
            % Accumulate; dF/dP = <dL/dp>, dF/dpp = ...
            %--------------------------------------------------------------
            dFdp  = dFdp  - dWdp/2  - dE.dP'*iS*E;
            dFdpp = dFdpp - dWdpp/2 - dE.dP'*iS*dE.dP;
            qp.ic = qp.ic           + dE.dP'*iS*dE.dP;
 
            % and quantities for M-Step
            %--------------------------------------------------------------
            EE    = E*E'+ EE;
            ECE   = ECE + ECEu + ECEp;
            
        end % sequence (nY)
 
        % augment with priors
        %------------------------------------------------------------------
        dFdp(ip)     = dFdp(ip)     - pp.ic*qp.e;
        dFdpp(ip,ip) = dFdpp(ip,ip) - pp.ic;
        qp.ic(ip,ip) = qp.ic(ip,ip) + pp.ic;
        qp.c         = inv(qp.ic);
             
        % evaluate objective function <L(t)>
        %==================================================================
        L = - trace(iS*EE)/2  ...                    % states (u)
            - trace(qp.e'*pp.ic*qp.e)/2;             % parameters (p)

 
        % if F is increasing, save expansion point and dervatives
        %------------------------------------------------------------------
        if L > Fe
            
            Fe      = L;
            te      = te*2;
            B.dFdp  = dFdp;
            B.dFdpp = dFdpp;
            B.qp    = qp;
            B.mp    = mp;
            
        else
            
            % otherwise, return to previous expansion point
            %--------------------------------------------------------------
            dFdp    = B.dFdp;
            dFdpp   = B.dFdpp;
            qp      = B.qp;
            mp      = B.mp;
            te      = min(te/2,1/4);
        end
 
        % E-step: update expectation (p)
        %==================================================================

        % update conditional expectation
        %------------------------------------------------------------------
        dp   = spm_dx(dFdpp,dFdp,{te});
        qp.e = qp.e + dp(ip);
        qp.p = spm_unvec(qp.e,qp.p);
        qp.b = spm_unvec(dp(ib),qp.b);
        mp   = mp + dp;

        % convergence (E-Step)
        %------------------------------------------------------------------
        if (dFdp'*dp < 1e-2) | (norm(dp,1) < TOL), break, end
        
    end % E-Step
    
    
    % M-step - hyperparameters (h = exp(l))
    %======================================================================
    mh     = zeros(nh,1);
    dFdh   = zeros(nh,1);
    dFdhh  = zeros(nh,nh);
    for iM = 1:nM
 
        % [re-]set precisions using ReML hyperparameter estimates
        %------------------------------------------------------------------
        iS    = Qp;
        for i = 1:nh
           iS = iS + Q{i}*exp(qh.h(i));
        end
        S     = inv(iS);
        dS    = ECE + EE - S*nY;
         
        % 1st-order derivatives: dFdh = dF/dh
        %------------------------------------------------------------------
        for i = 1:nh
            dPdh{i}        =  Q{i}*exp(qh.h(i));
            dFdh(i,1)      = -trace(dPdh{i}*dS)/2;
        end
 
        % 2nd-order derivatives: dFdhh
        %------------------------------------------------------------------
        for i = 1:nh
            for j = 1:nh
                dFdhh(i,j) = -trace(dPdh{i}*S*dPdh{j}*S*nY)/2;
            end
        end
        
        % hyperpriors
        %------------------------------------------------------------------
        qh.e  = qh.h  - ph.h;
        dFdh  = dFdh  - ph.ic*qh.e;
        dFdhh = dFdhh - ph.ic;
        
        % update ReML estimate of parameters
        %------------------------------------------------------------------
        dh    = spm_dx(dFdhh,dFdh);
        qh.h  = qh.h + dh;
        mh    = mh   + dh;
        
        % conditional covariance of hyperparameters
        %------------------------------------------------------------------
        qh.c = -inv(dFdhh);
 
        % convergence (M-Step)
        %------------------------------------------------------------------
        if (dFdh'*dh < 1e-2) || (norm(dh,1) < TOL), break, end
        
    end % M-Step
 
    % evaluate objective function (F)
    %======================================================================
    L   = - trace(iS*EE)/2  ...                % states (u)
          - trace(qp.e'*pp.ic*qp.e)/2  ...     % parameters (p)
          - trace(qh.e'*ph.ic*qh.e)/2  ...     % hyperparameters (h)
          + spm_logdet(qu_c)/(2*nD)  ...       % entropy q(u)
          + spm_logdet(qp.c)/2  ...            % entropy q(p)
          + spm_logdet(qh.c)/2  ...            % entropy q(h)
          - spm_logdet(pp.c)/2  ...            % entropy - prior p
          - spm_logdet(ph.c)/2  ...            % entropy - prior h
          + spm_logdet(iS)*nY/2 ...            % entropy - error
          - n*ny*nY*log(2*pi)/2;

    
    % if F is increasing, save expansion point and dervatives
    %----------------------------------------------------------------------
    if L > (Fm + 1e-2)

        Fm    = L;
        F(iN) = Fm;

        % save model-states (for each time point)
        %==================================================================
        for t = 1:length(qU)
            v     = spm_unvec(qU(t).v{1},v);
            x     = spm_unvec(qU(t).x{1},x);
            z     = spm_unvec(qE{t},{M.v});
            for i = 1:(nl - 1)
                QU.v{i + 1}(:,t) = spm_vec(v{i});
                try
                    QU.x{i}(:,t) = spm_vec(x{i});
                end
                QU.z{i}(:,t)     = spm_vec(z{i});
            end
            QU.v{1}(:,t)         = spm_vec(qU(t).y{1} - z{1});
            QU.z{nl}(:,t)        = spm_vec(z{nl});

            % and conditional covariances
            %--------------------------------------------------------------
            i       = [1:nx];
            QU.S{t} = qU(t).c(i,i);
            i       = [1:nv] + nx*n;
            QU.C{t} = qU(t).c(i,i);
        end
        
        % save condotional densities
        %--------------------------------------------------------------
        B.QU   = QU;
        B.qp   = qp;
        B.qh   = qh;

        % report and break if convergence
        %------------------------------------------------------------------
        figure(Fdem)
        spm_DEM_qU(QU)
        if np
            subplot(nl,4,4*nl)
            bar(full(Up*qp.e))
            xlabel({'parameters';'{minus prior}'})
            axis square, grid on
        end
        if length(F) > 2
            subplot(nl,4,4*nl - 1)
            plot(F(2:end))
            xlabel('updates')
            title('log-evidence')
            axis square, grid on
        end
        drawnow

        % report (EM-Steps)
        %------------------------------------------------------------------
        str{1} = sprintf('DEM: %i (%i:%i:%i)',iN,iD,iE,iM);
        str{2} = sprintf('F:%.6e',full(Fm));
        str{3} = sprintf('p:%.2e',full(mp'*mp));
        str{4} = sprintf('h:%.2e',full(mh'*mh));
        fprintf('%-16s%-24s%-16s%-16s\n',str{1:4})

    else

        % otherwise, return to previous expansion point and break
        %------------------------------------------------------------------
        QU   = B.QU;
        qp   = B.qp;
        qh   = B.qh;
        break
        
    end
end
 
% Assemble output arguments
%==========================================================================

% conditional moments of model-parameters (rotated into original space)
%--------------------------------------------------------------------------
qP.P   = spm_unvec(Up*qp.e + spm_vec(M.pE),M.pE);
qP.C   = Up*qp.c(ip,ip)*Up';
qP.V   = spm_unvec(diag(qP.C),M.pE);
 
% conditional moments of hyper-parameters (log-transformed)
%--------------------------------------------------------------------------
qH.h   = spm_unvec(qh.h,{{M.hE} {M.gE}});
qH.g   = qH.h{2};
qH.h   = qH.h{1};
qH.C   = qh.c;
qH.V   = spm_unvec(diag(qH.C),{{M.hE} {M.gE}});
qH.W   = qH.V{2};
qH.V   = qH.V{1};

% assign output variables
%--------------------------------------------------------------------------
DEM.M  = M;
DEM.U  = U;                   % causes
DEM.X  = X;                   % confounds
 
DEM.qU = QU;                  % conditional moments of model-states
DEM.qP = qP;                  % conditional moments of model-parameters
DEM.qH = qH;                  % conditional moments of hyper-parameters
 
DEM.F  = F;                   % [-ve] Free energy

warning(sw);
