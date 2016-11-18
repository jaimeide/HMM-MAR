function [hmm,Gamma,Xi,fehist] = hmmtrain(data,T,hmm,Gamma,residuals,fehist)
%
% Train Hidden Markov Model using using Variational Framework
%
% INPUTS:
%
% data          observations - a struct with X (time series) and C (classes)
% T             Number of time points for each time series
% hmm           hmm structure with options specified in hmm.train
% Gamma         Initial state courses
% residuals     in case we train on residuals, the value of those.
%
% OUTPUTS
% hmm           estimated HMMMAR model
% Gamma         estimated p(state | data)
% Xi            joint probability of past and future states conditioned on data
% fehist        historic of the free energies across iterations
% knocked       states knocked out by the Bayesian inference
%
% hmm.Pi          - intial state probability
% hmm.P           - state transition matrix
% hmm.state(k).$$ - whatever parameters there are in the observation model
%
% Author: Diego Vidaurre, OHBA, University of Oxford

if nargin<6, fehist=[];
elseif ~isempty(fehist), fprintf('Restarting at cycle %d \n',length(fehist)+1);
end
cyc_to_go = 0;
setxx;

hmm.train.ignore_MEX = tempname;

% Cache test for useMEX
if ( (ismac || isunix) && hmm.train.useMEX ==1 && exist('hidden_state_inference_mx', 'file') == 3 && (~isfield(hmm.train,'ignore_MEX') || exist(hmm.train.ignore_MEX, 'file') == 0 ))
    hmm.cache.useMEX = true;
else
    hmm.cache.useMEX = false;
    if isfield(hmm.train,'ignore_MEX')
        fclose(fopen(hmm.train.ignore_MEX, 'w')); % create file
    end
end

for cycle=1:hmm.train.cyc
    
    if hmm.train.updateGamma
        
        %%%% E step
        if hmm.K>1 || cycle==1
            % state inference
            [Gamma,~,Xi] = hsinference(data,T,hmm,residuals,[],XX);
            if any(isnan(Gamma(:))), 
                error('Gamma has NaN, probably due to problems of precision')
            end
            % any state to remove?
            [as,hmm,Gamma,Xi] = getactivestates(hmm,Gamma,Xi);
            if hmm.train.dropstates
                if any(as==0)
                    cyc_to_go = hmm.train.cycstogoafterevent;
                    data.C = data.C(:,as==1);
                    [Gamma,~,Xi] = hsinference(data,T,hmm,residuals,[],XX);
                end
                if sum(hmm.train.active)==1
                    fehist(end+1) = sum(evalfreeenergy(data.X,T,Gamma,Xi,hmm,residuals,XX));
                    if hmm.train.verbose
                        fprintf('cycle %i: All the points collapsed in one state, free energy = %g \n',cycle,fehist(end));
                    end
                    K = 1; break
                end
            end
            setxx;
        end

        %%%% Free energy computation
        fehist(end+1) = sum(evalfreeenergy(data.X,T,Gamma,Xi,hmm,residuals,XX));
        strwin = ''; if hmm.train.meancycstop>1, strwin = 'windowed'; end
        if cycle>(hmm.train.meancycstop+1) 
            chgFrEn = mean( fehist(end:-1:(end-hmm.train.meancycstop+1)) - ...
                fehist(end-1:-1:(end-hmm.train.meancycstop)) )  ...
                / (fehist(1) - fehist(end));
            if hmm.train.verbose, 
                fprintf('cycle %i free energy = %g, %s relative change = %g \n',...
                    cycle,fehist(end),strwin,chgFrEn); 
            end
            if (abs(chgFrEn) < hmm.train.tol) && cyc_to_go==0, break; end
        elseif hmm.train.verbose, 
            fprintf('cycle %i free energy = %g \n',cycle,fehist(end)); %&& cycle>1
        end
        if cyc_to_go>0, cyc_to_go = cyc_to_go - 1; end
        
    else
        Xi=[]; fehist=0;
    end
    
    %%%% M STEP
       
    % Observation model
    hmm = obsupdate(T,Gamma,hmm,residuals,XX,XXGXX);
    
    if hmm.train.updateGamma,
        % transition matrices and initial state
        hmm = hsupdate(Xi,Gamma,T,hmm);
    else
        break % one is more than enough
    end

end

if hmm.train.verbose
    fprintf('Model: %d states, %d data samples, covariance: %s \n', ...
        K,sum(T),hmm.train.covtype);
    if hmm.train.exptimelag>1,
        fprintf('Exponential lapse: %g, order %g, offset %g \n', ...
            hmm.train.exptimelag,hmm.train.order,hmm.train.orderoffset)
    else
        fprintf('Lapse: %d, order %g, offset %g \n', ...
            hmm.train.timelag,hmm.train.order,hmm.train.orderoffset)
    end
    if exist(hmm.train.ignore_MEX, 'file')>0
        fprintf('MEX file was not used, maybe due to some problem \n')
    else
        fprintf('MEX file was used for acceleration \n')
    end
end

if exist(hmm.train.ignore_MEX,'file')>0
    delete(hmm.train.ignore_MEX)
end
hmm.train = rmfield(hmm.train,'ignore_MEX');

% Problem was that the free energy is lower if states are knocked out
% That is, collapsing from 10 to 1 has a lower free energy than collapsing from 5 to 1
% Because of the change in dirichletdiag
%
% if size(Gamma,2) == 1
%     disp('----')
%     disp('----')
%     disp('OUTPUT')
%     sum(evalfreeenergy(data.X,T,Gamma,Xi,hmm,residuals,XX))
%     evalfreeenergy(data.X,T,Gamma,Xi,hmm,residuals,XX)
%     size(Gamma)
%     sum(Gamma)
%     sum(Xi)
% end

end
