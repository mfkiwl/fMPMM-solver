% fMPMM-solver: Fast and efficient MATLAB-based MPM solver
%
% Copyright (C) 2020  Emmanuel Wyser, Michel Jaboyedoff, Yury Podladchikov
% -------------------------------------------------------------------------%
% version    : v1.0
% date       : february, 2020
% description: explicit mpm (CPDI2q) solver based on an updated Lagrangian
% frame in plane strain condition for elasto-plastic problem discretized on
% a 4-noded quadrilateral mesh
% -------------------------------------------------------------------------%
%% FANCY CALLS
clear                                                                     ;%
addpath('functions')                                                      ;%   
version    = 'CPDI2q_EP_'                                                    ;%
plasticity = true                                                         ;%         
typeD='double'                                                            ;%
disp('EXACT PLASTIC CORRECTION')                                          ;%
disp('------------------------')                                          ;%

set(0,'defaulttextinterpreter','latex')                                   ;%
fslab  = 14; fsleg  = 14; fstit  = 14; fstick = 14;

numel = repmat(80,1,1)                                                    ;%
run   = zeros(length(numel),6)                                            ;%

for sim=1:length(numel)
    disp('------------------------')                                      ;%
    disp(['Run ',num2str(sim),': nel = ',num2str(numel(sim)),''])         ;%
    disp('------------------------')                                      ;%
    
    %% NON-DIMENSIONAL CONSTANT
    ar      = 0.8                                                         ;% aspect ratio thickness/width
    nu      = 0.3                                                         ;% poisson ratio
    ni      = 2                                                           ;% number of mp in h(1) direction
    nstr    = 4                                                           ;% number of stress components
    %---------------------------------------------------------------------%
    
    %% INDEPENDANT PHYSICAL CONSTANT
    g       = 9.81                                                        ;% gravitationnal acceleration [m/s^2]
    E       = 70.0e6                                                       ;% young's modulus             [Pa]
    Gc      = E/(2*(1+nu))                                                ;% shear modulus               [Pa]
    Kc      = E/(3*(1-2*nu))                                              ;% bulk modulus                [Pa]
    rho0    = 2100                                                        ;% density                     [kg/m^3]
    n0      = 0.25                                                        ;% initial porosity            [-]
    yd      = sqrt(E/rho0)                                                ;% elastic wave velocity       [m/s]
    coh0    = 10.0e3                                                      ;% cohesion                    [Pa]
    phi0    = 20.0*pi/180                                                 ;% friction angle              [Rad]
    t       = 15.0                                                         ;% simulation time             [s]
    te      = 8.0                                                         ;% elastic loading             [s]
    %---------------------------------------------------------------------%
    
    %% MESH & MP INITIALIZATION
    [meD,bc] = meSetup(numel(sim),typeD)                                  ;% - see function   
    ly      = 35                                                          ;% layer thickness [m]
    [mpD]   = mpSetup(meD,ni,ly,coh0,phi0,n0,rho0,nstr,typeD)   ;% - see function
    
    %figure(1),plot(meD.x,meD.y,'s',meD.x(bc.y(:,1)),meD.y(bc.y(:,1)),'gs',mpD.x(:,1),mpD.x(:,2),'x');axis equal;drawnow
  
    
    % ISOTROPIC ELASTIC MATRIX
    Del     = [ Kc+4/3*Gc,Kc-2/3*Gc,Kc-2/3*Gc,0.0;...
                Kc-2/3*Gc,Kc+4/3*Gc,Kc-2/3*Gc,0.0;...
                Kc-2/3*Gc,Kc-2/3*Gc,Kc+4/3*Gc,0.0;...
                0.0      ,0.0      ,0.0      ,Gc]                         ;%
    %---------------------------------------------------------------------%
    
    %% DISPLAY PARAMETERS AND RUNTIME INITIALIZATION
    fps  = 25                                                             ;% image per second
    %COURANT-FRIEDRICH-LEVY CONDITION
    dt   = 0.5*meD.h(1)/yd                                                ;% unconditionally stable timestep
    nit  = ceil(t/dt)                                                     ;% maximum number of interation
    nf   = max(2,ceil(round(1/dt)/fps))                                   ;% number of frame interval
    % GRAVITY INCREMENT
    dg   = linspace(0,g,round(((te)/1.5)/dt))                             ;% gravity increase
    % RUNTIME PARAMETERS
    nc   = 0                                                              ;% initialize iteration counter                                                         
    it   = 1                                                              ;% initialize iteration
    tw   = 0.0                                                            ;% initialize time while statement
    cycle_time = zeros(nit,7)                                             ;%
    % PLOT SETTING
    [pp] = plotSetup(meD.xB(1)+meD.L(1)/2,meD.xB(2)+meD.L(1)/2,meD.xB(3),40,meD.y,bc.y)         ;% - see function
    %---------------------------------------------------------------------%
    
    %% MPM DM ALGORITHM EXPLICIT SOLVER FOR INFINITESIMAL STRAIN
    fprintf('MPM SOLVER ON: %.0f elements \n'      ,meD.nEx*meD.nEy)      ;%
    fprintf('               %.0f nodes \n'         ,meD.nN)               ;%
    fprintf('               %.0f material point \n',mpD.n)                ;%    
    
    tsolve=tic                                                            ;%
    while((tw<t)||(sum(isnan(mpD.v(:,1))+isnan(mpD.v(:,2)))>0.0))          % BEGIN WHILE LOOP
        time_it= tic                                                      ;%
        dpi    = time_it                                                  ;% CURRENT ITERATION TIMER BEGIN
        %% LINEAR INCREASE OF GRAVITY FOR EQUILIBRIUM
        if(it<=size(dg,2))
            g = dg(it)                                                    ;% incremented gravity load
        end
        %------------------------------------------------------------------%
        
        %% TRACK MATERIAL POINTS CORNER (C) IN ELEMENTS (E)
        c2e  = reshape((permute((floor((mpD.yc-min(meD.y))./meD.h(2))+1)+...
               (meD.nEy).*floor((mpD.xc-min(meD.x))./meD.h(1)),[2 1])),mpD.n*4,1);%
        neon = length(unique(c2e));
        c2N  = reshape((meD.e2N(c2e,:)'),meD.nNp,mpD.n)';
        %------------------------------------------------------------------%
        
        %% BASIS FUNCTIONS
        tic;
        [mpD,N,mp,no] = SdS(mpD,meD,c2N)                                  ;% - see function 
        cycle_time(it,1)=toc;
        %------------------------------------------------------------------%
        %% PROJECTION FROM MATERIAL POINTS (p) TO NODES (N)
        tic
        [meD] = p2Nsolve(meD,mpD,g,dt,mp,no,bc)                           ;% - see function
        cycle_time(it,2)=toc; 
        %------------------------------------------------------------------%

        %% INTERPOLATION FROM NODAL SOLUTIONS (N) TO MATERIAL POINTS (p)
        tic
        [meD,mpD] = mapN2p(meD,mpD,dt,mp,no,bc)                           ;% - see function
        cycle_time(it,3)=toc;
        %------------------------------------------------------------------%
        
        %% UPDATE INCREMENTAL DEFORMATION & STRAIN 
        tic
        [mpD] = DefUpdate(meD,mpD,N,mp,no,c2N)                            ;% - see function
        cycle_time(it,4)=toc;
        %------------------------------------------------------------------%   
        
        %% ELASTO-PLASTIC RELATION: ELASTIC PREDICTOR - PLASTIC CORRECTOR
        tic
        [mpD] = constitutive(mpD,Del,Gc,Kc,nu,plasticity,dt,it,te)           ;%
        cycle_time(it,5)=toc                                              ;%
        dpi=toc(dpi)                                                      ;% CURRENT ITERATION TIMER END
        cycle_time(it,6)=dpi                                              ;%
        %------------------------------------------------------------------%
        
        %% TERMINAL DISPLAY
        if(mod(it,nf)==1)
            rt    = ((nit-it)*toc(time_it))                               ;%
            dpi   = mean(1./cycle_time(1:it,6))                           ;%
            clocktimer(rt,'Remaining estimated time:',dpi)                ;%
        end
        %------------------------------------------------------------------%        
       
        %% ITERATION INCREMENT
        tw=tw+dt                                                          ;%
        it=it+1                                                           ;%
        %------------------------------------------------------------------%
        
    end% END WHILE LOOP
    tsolve = toc(tsolve)                                                  ;%
    clocktimer(tsolve,'Runtime MPM solver:',mean(1./cycle_time(:,6)))     ;%
  
    fig1=figure(1)
    set(fig1,'Units','pixels','Position',[100 287.6667 541 241.3333]);
    pp.cbchar='$\log_{10}(\epsilon_{\mathrm{II}})$';
    pp.cbpos =[0.42 0.5 0.2 0.05];
    pos            = pp.cbpos;
    pp.cblpos=[pos(1)-(pos(3)) pos(2)+2];
    pp.caxis =log10(max(mpD.epII));
    %pp.tit   =['time: ',num2str(it*dt-te,'%.2f'),' (s), $e_{on}=',num2str(neon),'$, $n_p \in e_i = ',num2str(ni^2),'$ '];
    pp.tit   =['$t=',num2str(it*dt-te,'%.2f'),'$ (s)'];
    D = log10(mpD.epII);
    dis(D,mpD.x(:,1)+meD.L(1)/2,mpD.x(:,2),it*dt,pp);

    tit = {'D-P model: final geometry','D-P model: failure surface'};
    set(fig1, 'InvertHardCopy', 'off');

    fig2=figure(54363);
    clf
    set(fig2,'Units','pixels','Position',[100 200 1127 283]);
    xs=[mpD.xc mpD.xc(:,1)];
    ys=[mpD.yc mpD.yc(:,1)];
    plot(xs'+meD.L(1)/2,ys','k-');axis equal;axis tight;
    xlabel('$x$ (m)');ylabel('$y$ (m)');
    set(gca,'FontSize',15,'TickLabelInterpreter','latex');

    name=['.\data\CPDI2q_time_vectorized_' num2str(sim) '.mat'];
    save(name,'cycle_time');
    name=['.\data\data_' num2str(sim) '.mat'];
    save(name,'mpD','meD','ni','rho0','E','nu','dt','nit');
end
%% REFERENCE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%-------------------------------------------------------------------------%
% Dunatunga, S., Kamrin, K. (2017) Continuum modeling of projectile impact
% and penetration in dry granular media. J. Mech. Phys. Solids. 100. 45-60
%-------------------------------------------------------------------------%
% Dunatunga, S., Kamrin, K. (2015) Continuum modelling and simulation of
% granular flows through their many phases. J. Fluid Mech. 779. 483-513.
%-------------------------------------------------------------------------%
% Stomakhin, A., Schroeder, C., Chai, L., Teran, C., Selle, A. (2013) A
% material point method for snow simulation. ACM Trans. Graph. 32.
%-------------------------------------------------------------------------%
% Gaume, J., Gast, T., Teran, J., van Herwijnen, A., Jiang, C. (2018)
% Dynamic anticrack propagation in snow. Nat. Com. 9
%-------------------------------------------------------------------------%
% Wang, B., Vardon, P.J., Hicks, M.A. (2016) Investigation of retrogressive
% and progressive slope failure mechanisms using the material point method.
% Comp. and Geot. 78. 88-98
%-------------------------------------------------------------------------%
% Liang, W., Zhao, J. (2018) Multiscale modeling of large deformation in
% geomechanics. Int. J. Anal. Methods Geomech. 43. 1080-1114
%-------------------------------------------------------------------------%
% Baumgarten, A.S., Kamrin, K. (2018) A general fluid-sediment mixture
% model and constitutive theory validated in many flow regimes. J. Fluid
% Mech. 861. 7211-764.
%-------------------------------------------------------------------------%
% Huang, P., Zhang, X., Ma, S., Huang, X. (2011) Contact algorithms for the
% material point method in impact and penetration simulation. Int. J. Numer.
% Meth. Engng. 85. 498-517.
%-------------------------------------------------------------------------%
% Homel, M., Herbold, E.B. (2017) Field-gradient partitioning for fracture
% and frictional contact in the material point method. Int. J. Numer. Meth.
% Engng. 109. 1013-1044
%-------------------------------------------------------------------------%
% Ma. S., Zhank, X., Qui, X.M. (2009) Comparison study of MPM and SPH in
% modeling hypervelocity impact problems. Int. J. Imp. Engng. 36. 272-282.
%-------------------------------------------------------------------------%
% Bardenhagen, S.G., Brackbill, J.U., Sulsky, D. (2000) The material-point
% method for granular materials. Comput. Methods Appl. Mech. Engrg. 187.
% 529-541.
%-------------------------------------------------------------------------%
% York, A.R., Sulsky, D., Schreyer, H.L. (1999) The material point method
% for simulation of thin membranes. Int. J. Numer. Meth. Engng. 44. 1429-1456
%-------------------------------------------------------------------------%
% Nairn, J.A., Bardenhagen, S.G., Smith, G.D. (2018) Generalized contact
% and improved frictional heating in the material point method. Comp. Part.
% Mech. 3. 285-296
%-------------------------------------------------------------------------%
% Nairn, J.A. (2013) Modeling imperfect interfaces in the material point
% method using multimaterial methods. Comp. Mod. Engrg. Sci. 92. 271-299.
%-------------------------------------------------------------------------%
% Hammerquist, C.C., Nairn, J.A. (2018) Modeling nanoindentation using the
% material point method. J. Mater. Res. 33. 1369-1381
%-------------------------------------------------------------------------%
% Hamad, F., Stolle, D., Moormann, C. (2016) Material point modelling of
% releasing geocontainers from a barge. Geotext. Geomembr. 44. 308-318.
%-------------------------------------------------------------------------%
% Bhandari, T., Hamad, F., Moormann, C., Sharma, K.G., Westrich, B. (2016)
% Comp. Geotech. 75. 126-134.
%-------------------------------------------------------------------------%
% Wang, B., Vardon, P.J., Hicks, M.A. (2016) Investigation of retrogressive
% and progressive slope failure mechanisms using the material point method.
% Comp. Geotech. 78. 88-98.
%-------------------------------------------------------------------------%
% Keller, T., May, D.A., Kaus, B.J.P. (2013) Numerical modelling of magma
% dynamics oupled to tectonic deformation of lithosphere and crust.
% Geophys. J. Int. 195. 1406-1442.
