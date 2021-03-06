function [X,T,Gamma] = simhmmmar(T,hmm,Gamma,nrep,sim_state_tcs_only,grouping)
%
% Simulate data from the HMM-MAR
%
% INPUTS:
%
% T                     Number of time points for each time series
% hmm                   hmm structure with options specified in hmm.train
% Gamma                 State courses - leave these empty to simulate these too
% nrep                  no. repetitions of Gamma(t), from which we take the average
% X0                    A starting point for the time series ( no. time points x ndim x length(T) )
%                       - if not provided, it is set to Gaussian noise
% sim_state_tcs_only    Flag to indicate that only state time courses will be
%                       simulated
%
% OUTPUTS
% X             simulated observations  
% T             Number of time points for each time series
% Gamma         simulated  p(state | data)
%
% Author: Diego Vidaurre, OHBA, University of Oxford

N = length(T); K = length(hmm.state);
ndim = size(hmm.state(1).W.Mu_W,2);

if nargin<3, Gamma = []; end
if nargin<4 || isempty(nrep), nrep = 10; end
if nargin<5, sim_state_tcs_only=0; end
if nargin<6, grouping=[]; end
    
if ~isfield(hmm.train,'timelag'), hmm.train.timelag = 1; end
if ~isfield(hmm.train,'exptimelag'), hmm.train.exptimelag = 1; end
if ~isfield(hmm.train,'orderoffset'), hmm.train.orderoffset = 0; end
if ~isfield(hmm.train,'S'), hmm.train.S = ones(ndim); end
if ~isfield(hmm.train,'multipleConf'), hmm.train.multipleConf = 0; end
if ~isfield(hmm.train,'maxorder'), hmm.train.maxorder = hmm.train.order; end

if hmm.train.maxorder > 0, d = 500;
else, d = 0;
end

if isempty(Gamma) && K>1 % Gamma is not provided, so we simulate it too
    Gamma = simgamma(T,hmm.P,hmm.Pi,nrep,grouping);
elseif isempty(Gamma) && K==1
    Gamma = ones(sum(T),1);
end
if size(Gamma,1) ~= sum(T), error('Gamma should have sum(T) rows'); end

X = zeros(sum(T),ndim);
ind = false(sum(T),1);
hmm0 = hmm; hmm0.train.zeromean = 1; 

if ~sim_state_tcs_only
    for k=1:K
        if ~isfield(hmm.state(k),'train') || isempty(hmm.state(k).train)
            hmm.state(k).train = hmm.train;
        end
        if ~isfield(hmm.state(k).train,'orders')
            hmm.state(k).train.orders = ...
                formorders(hmm.state(k).train.order,...
                hmm.state(k).train.orderoffset,...
                hmm.state(k).train.timelag,...
                hmm.state(k).train.exptimelag);
        end
    end
    for n = 1:N
        t0 = sum(T(1:n-1)) + 1; t1 = sum(T(1:n));
        if hmm.train.maxorder > 0 % a MAR is generating the data
            Gamma0 = simgamma(d,hmm.P,hmm.Pi,nrep,grouping);
            X0 = simgauss(d,hmm0,Gamma0); % no mean in the innovation signal
        else % sampling Gaussian
            X0 = []; Gamma0 = [];
        end
        start = hmm.train.maxorder + 1;
        Xin = [X0; simgauss(T(n),hmm,Gamma(t0:t1,:))]; 
        if ~hmm.train.zeromean || hmm.train.maxorder > 0
            G = [Gamma0; Gamma(t0:t1,:)];
            for t=start:T(n)+d
                for k=1:K
                    orders = hmm.state(k).train.orders;
                    XX = zeros(1,length(orders)*ndim);
                    for i=1:length(orders)
                        o = orders(i);
                        XX(1,(1:ndim) + (i-1)*ndim) = Xin(t-o,:);
                    end
                    if ~hmm.train.zeromean
                        XX = [1 XX];
                    end
                    Xin(t,:) = Xin(t,:) + G(t,k) * XX * hmm.state(k).W.Mu_W;
                end
            end
        end
        ind(t0+hmm.train.maxorder : t1) = true;
        X(t0:t1,:) = Xin(d+1:end,:);
    end
end

Gamma = Gamma(ind,:);


end

