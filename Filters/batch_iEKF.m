%% Iterated, Extended Kalman Filter (iEKF) Class
% *Author: Dylan Thomas*
%
% This class implements an iterated, extended Kalman filter.
%
% *Note: the user must instantiate the class with no properties, as a
% structure with fieldnames matching all input properties, or all input
% properties separately.

%% iEKF Class Definition
classdef batch_iEKF < batchFilter
    % Inherits batchFilter abstract class
    
    %% iEKF Properties
    % *Inputs:*
    properties
        
        nRK         % Scalar >= 5:
                    %
                    % The Runge Kutta iterations to perform for
                    % coverting dynamics model from continuous-time
                    % to discrete-time. Default value is 10 RK
                    % iterations.
        
        Niter       % Scalar >= 1:
                    %
                    % The number of measurement update iterations to
                    % run through. Default value is 5.
        
        alphalim    % Scalar between 1 and 0:
                    %
                    % The lower limit for the Gauss-Newton step
                    % change. This limit decreases until the cost
                    % function is decreased for the current state
                    % estimate. If the cost function is not
                    % decreased, then the alpha value is decreased
                    % to create a different state estimate. Default
                    % value is 0.01.
    end
    
    %% iEKF Methods
    methods
        % iEKF constructor
        % Input order:
        % fmodel,hmodel,modelFlag,kInit,xhatInit,PInit,uhist,zhist,thist,Q,R,nRK,Niter,alphalim
        function iEKFobj = batch_iEKF(varargin)
            % Prepare for superclass constructor
            if nargin == 0
                fprintf('Instantiating empty batch iEKF class\n\n')
                super_args = {};
            elseif nargin == 1
                fprintf('Instantiating batch iEKF class\n\n')
                super_args = varargin{1};
            elseif nargin < 11
                error('Not enough input arguments')
            else
                fprintf('Instantiating batch iEKF class\n\n')
                super_args = cell(1,12);
                for jj = 1:11
                    super_args{jj} = varargin{jj};
                end
            end
            % batchFilter superclass constructor
            iEKFobj@batchFilter(super_args{:});
            % Only do if intantiated class is not empty
            if nargin > 0
                % Extra argument checker method
                iEKFobj = argumentsCheck(iEKFobj);
            end
        end
        
        % This method checks the extra input arguments for iEKF class
        function iEKFobj = argumentsCheck(iEKFobj)
            % Switch on number of extra arguments.
            switch length(iEKFobj.optArgs)
                case 0
                    iEKFobj.nRK = 10;
                    iEKFobj.Niter = 5;
                    iEKFobj.alphalim = 0.01;
                case 1
                    iEKFobj.nRK = iEKFobj.optArgs{1};
                    iEKFobj.Niter = 5;
                    iEKFobj.alphalim = 0.01;
                case 2
                    iEKFobj.nRK = iEKFobj.optArgs{1};
                    iEKFobj.Niter = iEKFobj.optArgs{2};
                    iEKFobj.alphalim = 0.01;
                case 3
                    iEKFobj.nRK = iEKFobj.optArgs{1};
                    iEKFobj.Niter = iEKFobj.optArgs{2};
                    iEKFobj.alphalim = iEKFobj.optArgs{3};
                otherwise
                    error('Too many input arguments')
            end
            % Ensures extra input arguments have sensible values.
            if iEKFobj.nRK < 5
                error('Number of Runge-Kutta iterations should be larger than 5')
            elseif (iEKFobj.Niter > 1000 || iEKFobj.Niter < 1)
                error('The number of measurement update iterations is too large')
            elseif (iEKFobj.alphalim >= 1 || iEKFobj.alphalim <= 0)
                error('Lower bound on alpha should be between 0 and 1')
            end
        end
        
        % This method initializes the iEKF class filter
        function [iEKFobj,xhatk,Pk,tk,vk] = initFilter(iEKFobj)
            % Setup the output arrays
            iEKFobj.xhathist     = zeros(iEKFobj.nx,iEKFobj.kmax+1);
            iEKFobj.Phist        = zeros(iEKFobj.nx,iEKFobj.nx,iEKFobj.kmax+1);
            iEKFobj.eta_nuhist   = zeros(size(iEKFobj.thist));
            
            % Initialize quantities for use in the main loop and store the
            % first a posteriori estimate and its error covariance matrix.
            xhatk                                  = iEKFobj.xhatInit;
            Pk                                     = iEKFobj.PInit;
            iEKFobj.xhathist(:,iEKFobj.kInit+1)    = iEKFobj.xhatInit;
            iEKFobj.Phist(:,:,iEKFobj.kInit+1)     = iEKFobj.PInit;
            vk                                     = zeros(iEKFobj.nv,1);
            % Make sure correct initial tk is used.
            if iEKFobj.kInit == 0
                tk = 0;
            else
                tk = iEKFobj.thist(iEKFobj.kInit);
            end
        end
        
        % This method performs iEKF class filter estimation
        function iEKFobj = doFilter(iEKFobj)
            % Filter initialization method
            [iEKFobj,xhatk,Pk,tk,vk] = initFilter(iEKFobj);
            
            % Main filter loop.
            for k = iEKFobj.kInit:(iEKFobj.kmax-1)
                % Prepare loop
                kp1 = k+1;
                tkp1 = iEKFobj.thist(kp1);
                uk = iEKFobj.uhist(kp1,:)';
                
                % Perform dynamic propagation and measurement update
                [xbarkp1,Pbarkp1] = dynamicProp(iEKFobj,xhatk,Pk,uk,vk,tk,tkp1,k);
                [xhatkp1,Pkp1,eta_nukp1] = measUpdate(iEKFobj,xbarkp1,Pbarkp1,kp1);
                
                % Store results
                kp2 = kp1 + 1;
                iEKFobj.xhathist(:,kp2) = xhatkp1;
                iEKFobj.Phist(:,:,kp2) = Pkp1;
                iEKFobj.eta_nuhist(kp1) = eta_nukp1;
                % Prepare for next sample
                xhatk = xhatkp1;
                Pk = Pkp1;
                tk = tkp1;
            end
        end
        
        % Dynamic propagation method, from sample k to sample k+1.
        function [xbarkp1,Pbarkp1] = dynamicProp(iEKFobj,xhatk,Pk,uk,vk,tk,tkp1,k)
            % Check model types and get sample k a priori state estimate.
            if strcmp(iEKFobj.modelFlag,'CD')
                [xbarkp1,F,Gamma] = c2dnonlinear(xhatk,uk,vk,tk,tkp1,iEKFobj.nRK,iEKFobj.fmodel,1);
            elseif strcmp(iEKFobj.modelFlag,'DD')
                [xbarkp1,F,Gamma] = feval(iEKFobj.fmodel,xhatk,uk,vk,k);
            else
                error('Incorrect flag for the dynamics-measurement models')
            end
            % Get sample k a priori error covariance
            Pbarkp1 = F*Pk*(F') + Gamma*iEKFobj.Q*(Gamma');
        end
        
        % Measurement update method at sample k+1.
        function [xhatkp1,Pkp1,eta_nukp1] = measUpdate(iEKFobj,xbarkp1,Pbarkp1,kp1)
            % Regular EKF measurement update 
            
            % Linearized at sample k+1 a priori state estimate.
            [zbarkp1,H] = feval(iEKFobj.hmodel,xbarkp1,kp1,1);
            zkp1 = iEKFobj.zhist(kp1,:)';
            % Innovations, innovation covariance, and filter gain.
            nukp1 = zkp1-zbarkp1;
            Skp1 = H*Pbarkp1*(H') + iEKFobj.R;
            Wkp1 = (Pbarkp1*(H'))/Skp1;
            % LMMSE sample k+1 a posteriori state estimate and covariance.
            xhatkp1 = xbarkp1 + Wkp1*nukp1;
            Pkp1 = Pbarkp1 - Wkp1*Skp1*(Wkp1');
            % Innovation statistics
            eta_nukp1 = nukp1'*(Skp1\nukp1);
            
            % Check if MAP iterations are to be performed
            if iEKFobj.Niter > 1
                % Initialize the measurement update iteration-loop
                xhati = xbarkp1;
                % Define cost function to minimize
                Jc = @(xkp1,hkp1)  (xkp1-xbarkp1)'*(Pbarkp1\(xkp1-xbarkp1)) + (zkp1-hkp1)'*(iEKFobj.R\(zkp1-hkp1));
                % Loop through Niter iterations
                for ii = 2:iEKFobj.Niter
                    % Linearize at ith MAP state estimate.
                    [zbari,Hi] = feval(iEKFobj.hmodel,xhati,kp1,1);
                    % Innovations, innovation covariance, and filter gain.
                    nu = zkp1-zbari;
                    S = Hi*Pbarkp1*(Hi') + iEKFobj.R;
                    W = (Pbarkp1*(Hi'))/S;
                    % LMMSE sample k+1 a posteriori state estimate and covariance.
                    xhatip1 = xhati + W*nu;
                    % Calculate cost function at current state estimate
                    Jcold = Jc(xhati,zbari);
                    
                    % NOTE: The calculated (i+1)th MAP state estimate may
                    % not necessarily decrease the cost function, so we
                    % perform a loop with Gauss-Newton steps to ensure
                    % either that the cost function is decreased, or that
                    % the lower limit of our step is reached.
                    
                    % Initialize Gauss-Newton loop
                    alpha = 1; Jcnew = Jcold;
                    while (alpha >= iEKFobj.alphalim && Jcnew >= Jcold)
                        % Gauss-Newton step to find new MAP state estimate
                        xhatip1new = xhati + alpha*(xhatip1-xhati);
                        % Re-linearize about new state estimate @ (i+1)th step
                        [zbarip1,Hip1] = feval(iEKFobj.hmodel,xhatip1new,kp1,1);
                        % The a posteriori state estimate and error covariance
                        invP = inv(Pbarkp1)+(Hip1')*(iEKFobj.R\Hip1);
                        % Innovations and innovation statistics
                        nu = zkp1-zbarip1;
                        S = Hip1*(invP\(Hip1')) + iEKFobj.R;
                        W = (Pbarkp1*(Hip1'))/S;
                        % LMMSE sample k+1 a posteriori state estimate and covariance.
                        Pip1 = invP^-1;
                        eta_nuip1 = nu'*(S\nu);
                        
                        % Calculate new cost function at MAP state estimate
                        Jcnew = Jc(xhatip1new,zbarip1);
                        % Decrease alpha
                        alpha = alpha/2;
                    end
                    % Debug print
%                     fprintf('alpha at term: %4.5f\n',alpha)
                    % Check norm condition so that iterations aren't wasteful
                    if (norm(xhati-xhatip1new)/norm(xhati) < 1e-12)
                        % Debug print
%                         fprintf('norm condition reached at iter: %i\n',ii)
                        break
                    end
                    % Update for next loop
                    xhati = xhatip1new;
                end
                
                % The a posteriori error covariance, state estimate, &
                % error statistics
                xhatkp1 = xhati;
                Pkp1 = Pip1;
                eta_nukp1 = eta_nuip1;
            end
        end
    end
end