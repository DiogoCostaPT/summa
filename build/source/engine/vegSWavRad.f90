module vegSWavRad_module
! Numerical recipes data types
USE nrtype
! look-up values for the choice of canopy shortwave radiation method
USE mDecisions_module,only:  &
 noah_mp,                    & ! full Noah-MP implementation (including albedo)
 CLM_2stream,                & ! CLM 2-stream model (see CLM documentation)
 UEB_2stream,                & ! UEB 2-stream model (Mahat and Tarboton, WRR 2011)
 NL_scatter,                 & ! Simplified method Nijssen and Lettenmaier (JGR 1999)
 BeersLaw                      ! Beer's Law (as implemented in VIC)
! -------------------------------------------------------------------------------------------------
implicit none
private
public::vegSWavRad
! dimensions
integer(i4b),parameter        :: nBands=2      ! number of spectral bands for shortwave radiation
! named variables
integer(i4b),parameter        :: ist     = 1   ! Surface type:  IST=1 => soil;  IST=2 => lake
! spatial indices
integer(i4b),parameter        :: iLoc    = 1   ! i-location
integer(i4b),parameter        :: jLoc    = 1   ! j-location
! algorithmic parameters
real(dp),parameter     :: missingValue=-9999._dp  ! missing value, used when diagnostic or state variables are undefined
real(dp),parameter     :: verySmall=1.e-6_dp   ! used as an additive constant to check if substantial difference among real numbers
real(dp),parameter     :: mpe=1.e-6_dp         ! prevents overflow error if division by zero 
real(dp),parameter     :: dx=1.e-6_dp          ! finite difference increment
! control
logical(lgt)           :: printflag            ! flag to turn on printing
contains

 ! ************************************************************************************************
 ! new subroutine: muster program to compute energy fluxes at vegetation and ground surfaces
 ! ************************************************************************************************
 subroutine vegSWavRad(&
                       ! input: model control
                       vegTypeIndex,                                       & ! intent(in): index of vegetation type
                       soilTypeIndex,                                      & ! intent(in): index of soil type
                       computeVegFlux,                                     & ! intent(in): logical flag to compute vegetation fluxes (.false. if veg buried by snow)
                       ix_canopySrad,                                      & ! intent(in): index of method used for transmission of shortwave rad through the canopy
                       ! input: model variables
                       scalarCosZenith,                                    & ! intent(in): cosine of direct zenith angle (0-1)
                       spectralIncomingDirect,                             & ! intent(in): incoming direct solar radiation in each wave band (w m-2)
                       spectralIncomingDiffuse,                            & ! intent(in): incoming diffuse solar radiation in each wave band (w m-2)
                       spectralSnowAlbedoDirect,                           & ! intent(in): direct albedo of snow in each spectral band (-)
                       spectralSnowAlbedoDiffuse,                          & ! intent(in): diffuse albedo of snow in each spectral band (-)
                       scalarExposedLAI,                                   & ! intent(in): exposed leaf area index after burial by snow (m2 m-2)
                       scalarExposedSAI,                                   & ! intent(in): exposed stem area index after burial by snow (m2 m-2)
                       scalarVegFraction,                                  & ! intent(in): vegetation fraction (=1 forces no canopy gaps and open areas in radiation routine)
                       scalarCanopyWetFraction,                            & ! intent(in): fraction of lai, sai that is wetted (-)
                       scalarGroundSnowFraction,                           & ! intent(in): fraction of ground that is snow covered (-)
                       scalarVolFracLiqUpper,                              & ! intent(in): volumetric liquid water content in the upper-most soil layer (-)
                       scalarCanopyTempTrial,                              & ! intent(in): canopy temperature (K)
                       ! output
                       spectralBelowCanopyDirect,                          & ! intent(out): downward direct flux below veg layer (W m-2)
                       spectralBelowCanopyDiffuse,                         & ! intent(out): downward diffuse flux below veg layer (W m-2)
                       scalarBelowCanopySolar,                             & ! intent(out): radiation transmitted below the canopy (W m-2)
                       scalarCanopyAbsorbedSolar,                          & ! intent(out): radiation absorbed by the vegetation canopy (W m-2)
                       scalarGroundAbsorbedSolar,                          & ! intent(out): radiation absorbed by the ground (W m-2)
                       scalarCanopySunlitFraction,                         & ! intent(out): sunlit fraction of canopy (-)
                       scalarCanopySunlitLAI,                              & ! intent(out): sunlit leaf area (-)
                       scalarCanopyShadedLAI,                              & ! intent(out): shaded leaf area (-)
                       scalarCanopySunlitPAR,                              & ! intent(out): average absorbed par for sunlit leaves (w m-2)
                       scalarCanopyShadedPAR,                              & ! intent(out): average absorbed par for shaded leaves (w m-2)
                       err,message)                                          ! intent(out): error control
 ! utilities
 USE expIntegral_module,only:expIntegral                                     ! subroutine to calculate the exponential integral
 ! Noah-MP modules
 USE NOAHMP_ROUTINES,only:twoStream                                          ! two-stream radiative transfer
 ! Noah vegetation tables
 USE NOAHMP_VEG_PARAMETERS, only: RHOS,RHOL                                  ! Noah-MP: stem and leaf reflectance for each wave band
 USE NOAHMP_VEG_PARAMETERS, only: TAUS,TAUL                                  ! Noah-MP: stem and leaf transmittance for each wave band
 ! input
 integer(i4b),intent(in)        :: vegTypeIndex                              ! vegetation type index
 integer(i4b),intent(in)        :: soilTypeIndex                             ! soil type index
 logical(lgt),intent(in)        :: computeVegFlux                            ! logical flag to compute vegetation fluxes (.false. if veg buried by snow)
 integer(i4b),intent(in)        :: ix_canopySrad                             ! choice of canopy shortwave radiation method
 real(dp),intent(in)            :: scalarCosZenith                           ! cosine of the solar zenith angle (0-1)
 real(dp),intent(in)            :: spectralIncomingDirect(:)                 ! incoming direct solar radiation in each wave band (w m-2)
 real(dp),intent(in)            :: spectralIncomingDiffuse(:)                ! incoming diffuse solar radiation in each wave band (w m-2)
 real(dp),intent(in)            :: spectralSnowAlbedoDirect(:)               ! direct albedo of snow in each spectral band (-)
 real(dp),intent(in)            :: spectralSnowAlbedoDiffuse(:)              ! diffuse albedo of snow in each spectral band (-)
 real(dp),intent(in)            :: scalarExposedLAI                          ! exposed leaf area index after burial by snow (m2 m-2)
 real(dp),intent(in)            :: scalarExposedSAI                          ! exposed stem area index after burial by snow (m2 m-2)
 real(dp),intent(in)            :: scalarVegFraction                         ! vegetation fraction (=1 forces no canopy gaps and open areas in radiation routine)
 real(dp),intent(in)            :: scalarCanopyWetFraction                   ! fraction of canopy that is wet (-)
 real(dp),intent(in)            :: scalarGroundSnowFraction                  ! fraction of ground that is snow covered (-)
 real(dp),intent(in)            :: scalarVolFracLiqUpper                     ! volumetric liquid water content in the upper-most soil layer (-)
 real(dp),intent(in)            :: scalarCanopyTempTrial                     ! trial value of canopy temperature (K)
 ! output
 real(dp),intent(out)           :: spectralBelowCanopyDirect(:)              ! downward direct flux below veg layer (W m-2)
 real(dp),intent(out)           :: spectralBelowCanopyDiffuse(:)             ! downward diffuse flux below veg layer (W m-2)
 real(dp),intent(out)           :: scalarBelowCanopySolar                    ! radiation transmitted below the canopy (W m-2)
 real(dp),intent(out)           :: scalarCanopyAbsorbedSolar                 ! radiation absorbed by the vegetation canopy (W m-2)
 real(dp),intent(out)           :: scalarGroundAbsorbedSolar                 ! radiation absorbed by the ground (W m-2)
 real(dp),intent(out)           :: scalarCanopySunlitFraction                ! sunlit fraction of canopy (-)
 real(dp),intent(out)           :: scalarCanopySunlitLAI                     ! sunlit leaf area (-)
 real(dp),intent(out)           :: scalarCanopyShadedLAI                     ! shaded leaf area (-)
 real(dp),intent(out)           :: scalarCanopySunlitPAR                     ! average absorbed par for sunlit leaves (w m-2)
 real(dp),intent(out)           :: scalarCanopyShadedPAR                     ! average absorbed par for shaded leaves (w m-2)
 integer(i4b),intent(out)       :: err                                       ! error code
 character(*),intent(out)       :: message                                   ! error message
 ! -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 ! local variables
 ! -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 ! general
 integer(i4b),parameter                :: ixVisible=1                        ! index of the visible wave band
 integer(i4b),parameter                :: ixNearIR=2                         ! index of the near infra-red wave band
 integer(i4b)                          :: iBand                              ! index of wave band
 integer(i4b)                          :: ic                                 ! 0=unit incoming direct; 1=unit incoming diffuse
 character(LEN=256)                    :: cmessage                           ! error message of downwind routine
 ! albedo
 real(dp),dimension(1:nBands)          :: spectralAlbGndDirect               ! direct  albedo of underlying surface (1:nBands) (-)
 real(dp),dimension(1:nBands)          :: spectralAlbGndDiffuse              ! diffuse albedo of underlying surface (1:nBands) (-)
 ! variables used in Nijssen-Lettenmaier method
 real(dp),parameter                    :: multScatExp=0.81_dp                ! multiple scattering exponent (-)
 real(dp),parameter                    :: bulkCanopyAlbedo=0.25_dp           ! bulk canopy albedo (-), smaller than actual canopy albedo because of shading in the canopy
 real(dp),dimension(1:nBands)          :: spectralIncomingSolar              ! total incoming solar radiation in each spectral band (W m-2)
 real(dp),dimension(1:nBands)          :: spectralGroundAbsorbedDirect       ! total direct radiation absorbed at the ground surface (W m-2)
 real(dp),dimension(1:nBands)          :: spectralGroundAbsorbedDiffuse      ! total diffuse radiation absorbed at the ground surface (W m-2)
 real(dp)                              :: scalarGroundAlbedo                 ! albedo of the ground surface (-)
 real(dp)                              :: fractionSolarReflected             ! fraction of solar radiation reflected (-)
 real(dp)                              :: Fdirect                            ! fraction of direct radiation (-)
 real(dp)                              :: tauInitial                         ! transmission in the absence of scattering and multiple reflections (-)
 real(dp)                              :: tauTotal                           ! transmission due to scattering and multiple reflections (-)
 ! variables used in Mahat-Tarboton method
 real(dp),parameter                    :: Frad_vis=0.5_dp                    ! fraction of radiation in the visible wave band (-)
 real(dp),parameter                    :: gProjParam=0.5_dp                  ! projected leaf and stem area in the solar direction (-)
 real(dp),parameter                    :: bScatParam=0.5_dp                  ! back scatter parameter (-)
 real(dp)                              :: transCoef                          ! transmission coefficient (-)
 real(dp)                              :: transCoefPrime                     ! "k-prime" coefficient (-)
 real(dp)                              :: groundAlbedoDirect                 ! direct ground albedo (-)
 real(dp)                              :: groundAlbedoDiffuse                ! diffuse ground albedo (-)
 real(dp)                              :: tauInfinite                        ! direct transmission for an infinite canopy (-)
 real(dp)                              :: betaInfinite                       ! direct upward reflection factor for an infinite canopy (-)
 real(dp)                              :: tauFinite                          ! direct transmission for a finite canopy (-)
 real(dp)                              :: betaFinite                         ! direct reflectance for a finite canopy (-)
 real(dp)                              :: vFactor                            ! scaled vegetation area used to compute diffuse radiation (-)
 real(dp)                              :: expi                               ! exponential integral (-)
 real(dp)                              :: taudInfinite                       ! diffuse transmission for an infinite canopy (-)
 real(dp)                              :: taudFinite                         ! diffuse transmission for a finite canopy (-)
 real(dp)                              :: betadFinite                        ! diffuse reflectance for a finite canopy (-)
 real(dp)                              :: refMult                            ! multiple reflection factor (-)
 real(dp)                              :: tauDirect                          ! total transmission of direct radiation (-)
 real(dp)                              :: tauDiffuse                         ! total transmission of diffuse radiation (-)
 real(dp)                              :: fractionRefDirect                  ! fraction of direct radiaiton lost to space (-)
 real(dp)                              :: fractionRefDiffuse                 ! fraction of diffuse radiaiton lost to space (-)
 real(dp),dimension(1:nBands)          :: spectralBelowCanopySolar           ! total below-canopy radiation for each wave band (W m-2)
 real(dp),dimension(1:nBands)          :: spectralTotalReflectedSolar        ! total reflected radiaion for each wave band (W m-2)
 real(dp),dimension(1:nBands)          :: spectralGroundAbsorbedSolar        ! radiation absorbed by the ground in each wave band (W m-2)
 real(dp),dimension(1:nBands)          :: spectralCanopyAbsorbedSolar        ! radiation absorbed by the canopy in each wave band (W m-2)
 ! vegetation properties used in 2-stream
 real(dp)                              :: scalarExposedVAI                   ! one-sided leaf+stem area index (m2/m2)
 real(dp)                              :: weightLeaf                         ! fraction of exposed VAI that is leaf
 real(dp)                              :: weightStem                         ! fraction of exposed VAI that is stem
 real(dp),dimension(1:nBands)          :: spectralVegReflc                   ! leaf+stem reflectance (1:nbands)
 real(dp),dimension(1:nBands)          :: spectralVegTrans                   ! leaf+stem transmittance (1:nBands)
 ! output from two-stream -- direct-beam
 real(dp),dimension(1:nBands)          :: spectralCanopyAbsorbedDirect       ! flux abs by veg layer (per unit incoming flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralTotalReflectedDirect       ! flux refl above veg layer (per unit incoming flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralDirectBelowCanopyDirect    ! down dir flux below veg layer (per unit in flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralDiffuseBelowCanopyDirect   ! down dif flux below veg layer (per unit in flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralCanopyReflectedDirect      ! flux reflected by veg layer   (per unit incoming flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralGroundReflectedDirect      ! flux reflected by ground (per unit incoming flux), (1:nBands)
 ! output from two-stream -- diffuse
 real(dp),dimension(1:nBands)          :: spectralCanopyAbsorbedDiffuse      ! flux abs by veg layer (per unit incoming flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralTotalReflectedDiffuse      ! flux refl above veg layer (per unit incoming flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralDirectBelowCanopyDiffuse   ! down dir flux below veg layer (per unit in flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralDiffuseBelowCanopyDiffuse  ! down dif flux below veg layer (per unit in flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralCanopyReflectedDiffuse     ! flux reflected by veg layer   (per unit incoming flux), (1:nBands)
 real(dp),dimension(1:nBands)          :: spectralGroundReflectedDiffuse     ! flux reflected by ground (per unit incoming flux), (1:nBands)
 ! output from two-stream -- scalar variables
 real(dp)                              :: scalarGproj                        ! projected leaf+stem area in solar direction
 real(dp)                              :: scalarBetweenCanopyGapFraction     ! between canopy gap fraction for beam (-)
 real(dp)                              :: scalarWithinCanopyGapFraction      ! within canopy gap fraction for beam (-)
 ! radiation fluxes
 real(dp)                              :: ext                                ! optical depth of direct beam per unit leaf + stem area
 real(dp)                              :: scalarCanopyShadedFraction         ! shaded fraction of the canopy
 real(dp)                              :: fractionLAI                        ! fraction of vegetation that is leaves
 real(dp)                              :: visibleAbsDirect                   ! direct-beam radiation absorbed in the visible part of the spectrum (W m-2)
 real(dp)                              :: visibleAbsDiffuse                  ! diffuse radiation absorbed in the visible part of the spectrum (W m-2)
 ! -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 ! initialize error control
 err=0; message='vegSWavRad/'

 ! compute the albedo of the ground surface
 call gndAlbedo(&
                ! input
                soilTypeIndex,                         & ! intent(in): index of soil type
                scalarGroundSnowFraction,              & ! intent(in): fraction of ground that is snow covered (-)
                scalarVolFracLiqUpper,                 & ! intent(in): volumetric liquid water content in upper-most soil layer (-)
                spectralSnowAlbedoDirect,              & ! intent(in): direct albedo of snow in each spectral band (-)
                spectralSnowAlbedoDiffuse,             & ! intent(in): diffuse albedo of snow in each spectral band (-)
                ! output
                spectralAlbGndDirect,                  & ! intent(out): direct  albedo of underlying surface (-)
                spectralAlbGndDiffuse,                 & ! intent(out): diffuse albedo of underlying surface (-)
                err,message)                             ! intent(out): error control

 ! initialize accumulated fluxes
 scalarBelowCanopySolar    = 0._dp  ! radiation transmitted below the canopy (W m-2)
 scalarCanopyAbsorbedSolar = 0._dp  ! radiation absorbed by the vegetation canopy (W m-2)
 scalarGroundAbsorbedSolar = 0._dp  ! radiation absorbed by the ground (W m-2)

 ! check for an early return (no radiation or no exposed canopy)
 if(.not.computeVegFlux .or. scalarCosZenith < tiny(scalarCosZenith))then
  ! set canopy radiation to zero
  scalarCanopySunlitFraction = 0._dp                ! sunlit fraction of canopy (-)
  scalarCanopySunlitLAI      = 0._dp                ! sunlit leaf area (-)
  scalarCanopyShadedLAI      = scalarExposedLAI     ! shaded leaf area (-)
  scalarCanopySunlitPAR      = 0._dp                ! average absorbed par for sunlit leaves (w m-2)
  scalarCanopyShadedPAR      = 0._dp                ! average absorbed par for shaded leaves (w m-2)
  ! compute below-canopy radiation
  do iBand=1,nBands
   ! (set below-canopy radiation to incoming radiation)
   if(scalarCosZenith > tiny(scalarCosZenith))then
    spectralBelowCanopyDirect(iBand)  = spectralIncomingDirect(iBand)
    spectralBelowCanopyDiffuse(iBand) = spectralIncomingDiffuse(iBand)
   else
    spectralBelowCanopyDirect(iBand)  = 0._dp 
    spectralBelowCanopyDiffuse(iBand) = 0._dp
   endif
   ! (accumulate radiation transmitted below the canopy)
   scalarBelowCanopySolar    = scalarBelowCanopySolar + &                                                  ! contribution from all previous wave bands
                               spectralBelowCanopyDirect(iBand) + spectralBelowCanopyDiffuse(iBand)        ! contribution from current wave band
   ! (accumulate radiation absorbed by the ground)
   scalarGroundAbsorbedSolar = scalarGroundAbsorbedSolar + &                                               ! contribution from all previous wave bands
                               spectralBelowCanopyDirect(iBand)*(1._dp - spectralAlbGndDirect(iBand)) + &  ! direct radiation from current wave band
                               spectralBelowCanopyDiffuse(iBand)*(1._dp - spectralAlbGndDiffuse(iBand))    ! diffuse radiation from current wave band
  end do  ! looping through wave bands
  return
 endif

 ! compute exposed leaf and stem area index
 scalarExposedVAI = scalarExposedLAI + scalarExposedSAI
 if(scalarExposedVAI < epsilon(scalarExposedVAI))then; err=20; message=trim(message)//'very small exposed vegetation area (covered with snow?)'; return; endif

 ! ============================================================================================================================================================
 ! ============================================================================================================================================================
 
 ! different options for radiation transmission
 select case(ix_canopySrad)

  ! -----------------------------------------------------------------------------------------------------------------------------------------------------------
  ! method of Nijssen and Lettenmaier (JGR, 1999)
  case(NL_scatter)

   ! define transmission coefficient (-)
   scalarGproj = gProjParam
   transCoef   = scalarGproj/scalarCosZenith

   ! compute transmission of direct radiation according to Beer's Law (-)
   tauFinite = exp(-transCoef*scalarExposedVAI)

   ! compute transmission of diffuse radiation (-) 
   vFactor      = scalarGproj*scalarExposedVAI
   call expIntegral(1,vFactor,expi,err,cmessage); if(err/=0)then; message=trim(message)//trim(cmessage); return; endif
   taudFinite = (1._dp - vFactor)*exp(-vFactor) + (vFactor**2._dp)*expi

   ! compute ground albedo (-)
   groundAlbedoDirect  = Frad_vis*spectralAlbGndDirect(ixVisible)  + (1._dp - Frad_vis)*spectralAlbGndDirect(ixNearIR)
   groundAlbedoDiffuse = Frad_vis*spectralAlbGndDiffuse(ixVisible) + (1._dp - Frad_vis)*spectralAlbGndDiffuse(ixNearIR)

   ! compute radiation in each spectral band (W m-2)
   do iBand=1,nBands

    ! compute total incoming solar radiation
    spectralIncomingSolar(iBand) = spectralIncomingDirect(iBand) + spectralIncomingDiffuse(iBand)

    ! compute fraction of direct radiation
    Fdirect = spectralIncomingDirect(iBand) / (spectralIncomingSolar(iBand) + verySmall)

    ! compute ground albedo (-)
    scalarGroundAlbedo = Fdirect*groundAlbedoDirect + (1._dp - Fdirect)*groundAlbedoDiffuse

    ! compute initial transmission in the absence of scattering and multiple reflections (-)
    tauInitial = Fdirect*tauFinite + (1._dp - Fdirect)*taudFinite

    ! compute increase in transmission due to scattering and multiple reflections (-)
    tauTotal = (tauInitial**multScatExp)/(1._dp - scalarGroundAlbedo*bulkCanopyAlbedo)

    ! compute below-canopy radiation (W m-2)
    spectralBelowCanopyDirect(iBand)  = spectralIncomingDirect(iBand)*tauTotal              ! direct radiation from current wave band
    spectralBelowCanopyDiffuse(iBand) = spectralIncomingDiffuse(iBand)*tauTotal             ! diffuse radiation from current wave band
    spectralBelowCanopySolar(iBand)   = spectralBelowCanopyDirect(iBand) + spectralBelowCanopyDiffuse(iBand)

    ! compute fraction of solar radiation reflected (-)
    fractionSolarReflected = bulkCanopyAlbedo + tauTotal*scalarGroundAlbedo*taudFinite
    if(fractionSolarReflected > 1._dp)then
     message=trim(message)//'NL_scatter: fractionSolarReflected > 1'
     err=20; return
    endif

    ! compute solar radiation lost to space in given wave band (W m-2)
    spectralTotalReflectedDirect(iBand)  = spectralIncomingDirect(iBand)*fractionSolarReflected
    spectralTotalReflectedDiffuse(iBand) = spectralIncomingDiffuse(iBand)*fractionSolarReflected
    spectralTotalReflectedSolar(iBand)   = spectralTotalReflectedDirect(iBand) + spectralTotalReflectedDiffuse(iBand)

    ! compute radiation absorbed by the ground in given wave band (W m-2)
    spectralGroundAbsorbedDirect(iBand)  = (1._dp - scalarGroundAlbedo)*spectralBelowCanopyDirect(iBand)
    spectralGroundAbsorbedDiffuse(iBand) = (1._dp - scalarGroundAlbedo)*spectralBelowCanopyDiffuse(iBand)
    spectralGroundAbsorbedSolar(iBand)   = spectralGroundAbsorbedDirect(iBand) + spectralGroundAbsorbedDiffuse(iBand)

    ! compute radiation absorbed by vegetation in current wave band (W m-2)
    spectralCanopyAbsorbedDirect(iBand)  = spectralIncomingDirect(iBand) - spectralTotalReflectedDirect(iBand) - spectralGroundAbsorbedDirect(iBand)
    spectralCanopyAbsorbedDiffuse(iBand) = spectralIncomingDiffuse(iBand) - spectralTotalReflectedDiffuse(iBand) - spectralGroundAbsorbedDiffuse(iBand)
    spectralCanopyAbsorbedSolar(iBand)   = spectralCanopyAbsorbedDirect(iBand) + spectralCanopyAbsorbedDiffuse(iBand)

    ! save canopy radiation absorbed in visible wavelengths
    if(iBand == ixVisible)then
     visibleAbsDirect  = spectralCanopyAbsorbedDirect(ixVisible)
     visibleAbsDiffuse = spectralCanopyAbsorbedDiffuse(ixVisible)
    endif

    ! accumulate fluxes
    scalarBelowCanopySolar    = scalarBelowCanopySolar + spectralBelowCanopySolar(iBand)
    scalarGroundAbsorbedSolar = scalarGroundAbsorbedSolar + spectralGroundAbsorbedSolar(iBand)
    scalarCanopyAbsorbedSolar = scalarCanopyAbsorbedSolar + spectralCanopyAbsorbedSolar(iBand)

   end do  ! (looping through spectral bands)



  ! -----------------------------------------------------------------------------------------------------------------------------------------------------------
  ! method of Mahat and Tarboton (WRR, 2012)
  case(UEB_2stream)

   ! define transmission coefficient (-)
   scalarGproj = gProjParam
   transCoef   = scalarGproj/scalarCosZenith

   ! define "k-prime" coefficient (-)
   transCoefPrime = sqrt(1._dp - bScatParam)

   ! compute ground albedo (-)
   groundAlbedoDirect  = Frad_vis*spectralAlbGndDirect(ixVisible)  + (1._dp - Frad_vis)*spectralAlbGndDirect(ixNearIR)
   groundAlbedoDiffuse = Frad_vis*spectralAlbGndDiffuse(ixVisible) + (1._dp - Frad_vis)*spectralAlbGndDiffuse(ixNearIR)

   ! compute transmission for an infinite canopy (-)
   tauInfinite = exp(-transCoef*transCoefPrime*scalarExposedVAI)

   ! compute upward reflection factor for an infinite canopy (-)
   betaInfinite = (1._dp - transCoefPrime)/(1._dp + transCoefPrime)

   ! compute transmission for a finite canopy (-)
   tauFinite = tauInfinite*(1._dp - betaInfinite**2._dp)/(1._dp - (betaInfinite**2._dp)*tauInfinite**2._dp)

   ! compute reflectance for a finite canopy (-)
   betaFinite = betaInfinite*(1._dp - tauInfinite**2._dp) / (1._dp - (betaInfinite**2._dp)*(tauInfinite**2._dp))

   ! compute transmission of diffuse radiation (-)
   vFactor      = transCoefPrime*scalarGproj*scalarExposedVAI
   call expIntegral(1,vFactor,expi,err,cmessage); if(err/=0)then; message=trim(message)//trim(cmessage); return; endif
   taudInfinite = (1._dp - vFactor)*exp(-vFactor) + (vFactor**2._dp)*expi
   taudFinite   = taudInfinite*(1._dp - betaInfinite**2._dp)/(1._dp - (betaInfinite**2._dp)*taudInfinite**2._dp)

   ! compute reflectance of diffuse radiation (-)
   betadFinite  = betaInfinite*(1._dp - taudInfinite**2._dp) / (1._dp - (betaInfinite**2._dp)*(taudInfinite**2._dp))

   ! compute total transmission of direct and diffuse radiation, accounting for multiple reflections (-)
   refMult    = 1._dp / (1._dp - groundAlbedoDiffuse*betadFinite*(1._dp - taudFinite) )
   tauDirect  = tauFinite*refMult
   tauDiffuse = taudFinite*refMult

   ! compute fraction of radiation lost to space (-)
   fractionRefDirect  = ( (1._dp - groundAlbedoDirect)*betaFinite   + groundAlbedoDirect*tauFinite*taudFinite) * refMult
   fractionRefDiffuse = ( (1._dp - groundAlbedoDiffuse)*betadFinite + groundAlbedoDiffuse*taudFinite*taudFinite) * refMult

   ! compute radiation in each spectral band (W m-2)
   do iBand=1,nBands

    ! compute below-canopy radiation (W m-2)
    spectralBelowCanopyDirect(iBand)  = spectralIncomingDirect(iBand)*tauDirect                ! direct radiation from current wave band
    spectralBelowCanopyDiffuse(iBand) = spectralIncomingDiffuse(iBand)*tauDiffuse              ! diffuse radiation from current wave band
    spectralBelowCanopySolar(iBand)   = spectralBelowCanopyDirect(iBand) + spectralBelowCanopyDiffuse(iBand)

    ! compute solar radiation lost to space in given wave band (W m-2)
    spectralTotalReflectedDirect(iBand)  = spectralIncomingDirect(iBand)*fractionRefDirect
    spectralTotalReflectedDiffuse(iBand) = spectralIncomingDiffuse(iBand)*fractionRefDiffuse
    spectralTotalReflectedSolar(iBand)   = spectralTotalReflectedDirect(iBand) + spectralTotalReflectedDiffuse(iBand)

    ! compute radiation absorbed by the ground in given wave band (W m-2)
    spectralGroundAbsorbedDirect(iBand)  = (1._dp - groundAlbedoDirect)*refMult*spectralBelowCanopyDirect(iBand)
    spectralGroundAbsorbedDiffuse(iBand) = (1._dp - groundAlbedoDiffuse)*refMult*spectralBelowCanopyDiffuse(iBand)
    spectralGroundAbsorbedSolar(iBand)   = spectralGroundAbsorbedDirect(iBand) + spectralGroundAbsorbedDiffuse(iBand)

    ! compute radiation absorbed by vegetation in current wave band (W m-2)
    spectralCanopyAbsorbedDirect(iBand)  = spectralIncomingDirect(iBand) - spectralTotalReflectedDirect(iBand) - spectralGroundAbsorbedDirect(iBand)
    spectralCanopyAbsorbedDiffuse(iBand) = spectralIncomingDiffuse(iBand) - spectralTotalReflectedDiffuse(iBand) - spectralGroundAbsorbedDiffuse(iBand)
    spectralCanopyAbsorbedSolar(iBand)   = spectralCanopyAbsorbedDirect(iBand) + spectralCanopyAbsorbedDiffuse(iBand)

    ! save canopy radiation absorbed in visible wavelengths
    if(iBand == ixVisible)then
     visibleAbsDirect  = spectralCanopyAbsorbedDirect(ixVisible)
     visibleAbsDiffuse = spectralCanopyAbsorbedDiffuse(ixVisible)
    endif

    ! check fluxes balance
    if(spectralTotalReflectedSolar(iBand) + spectralGroundAbsorbedSolar(iBand) > spectralIncomingSolar(iBand))then
     message=trim(message)//'UEB_2stream: total radiation reflected plus radiation absorbed at the ground surface > total incoming radiation'
     err=20; return
    endif

    ! accumulate fluxes
    scalarBelowCanopySolar    = scalarBelowCanopySolar + spectralBelowCanopySolar(iBand)
    scalarGroundAbsorbedSolar = scalarGroundAbsorbedSolar + spectralGroundAbsorbedSolar(iBand)
    scalarCanopyAbsorbedSolar = scalarCanopyAbsorbedSolar + spectralCanopyAbsorbedSolar(iBand)

   end do  ! (looping through wave bands)



  ! -----------------------------------------------------------------------------------------------------------------------------------------------------------
  ! CLM approach
  case(CLM_2stream)

   ! weight reflectance and transmittance by exposed leaf and stem area index
   weightLeaf       = scalarExposedLAI / scalarExposedVAI
   weightStem       = scalarExposedSAI / scalarExposedVAI
   do iBand = 1,nBands  ! loop through spectral bands
    spectralVegReflc(iBand) = RHOL(vegTypeIndex,iBand)*weightLeaf + RHOS(vegTypeIndex,iBand)*weightStem
    spectralVegTrans(iBand) = TAUL(vegTypeIndex,iBand)*weightLeaf + TAUS(vegTypeIndex,iBand)*weightStem
   end do  

   ! loop through wave bands
   do iBand=1,nBands

    ic = 0
    ! two-stream approximation for direct-beam radiation (from CLM/Noah-MP)
    call twoStream(&
                   ! input
                   iBand,                             & ! intent(in): waveband number
                   ic,                                & ! intent(in): 0=unit incoming direct; 1=unit incoming diffuse
                   vegTypeIndex,                      & ! intent(in): vegetation type
                   scalarCosZenith,                   & ! intent(in): cosine of direct zenith angle (0-1)
                   scalarExposedVAI,                  & ! intent(in): one-sided leaf+stem area index (m2/m2)
                   scalarCanopyWetFraction,           & ! intent(in): fraction of lai, sai that is wetted (-)
                   scalarCanopyTempTrial,             & ! intent(in): surface temperature (k)
                   spectralAlbGndDirect,              & ! intent(in): direct  albedo of underlying surface (1:nBands) (-)
                   spectralAlbGndDiffuse,             & ! intent(in): diffuse albedo of underlying surface (1:nBands) (-)
                   spectralVegReflc,                  & ! intent(in): leaf+stem reflectance (1:nbands)
                   spectralVegTrans,                  & ! intent(in): leaf+stem transmittance (1:nBands)
                   scalarVegFraction,                 & ! intent(in): vegetation fraction (=1 forces no canopy gaps and open areas in radiation routine)
                   ist,                               & ! intent(in): surface type
                   iLoc,jLoc,                         & ! intent(in): grid indices
                   ! output
                   spectralCanopyAbsorbedDirect,      & ! intent(out): flux abs by veg layer (per unit incoming flux), (1:nBands)
                   spectralTotalReflectedDirect,      & ! intent(out): flux refl above veg layer (per unit incoming flux), (1:nBands)
                   spectralDirectBelowCanopyDirect,   & ! intent(out): down dir flux below veg layer (per unit in flux), (1:nBands)
                   spectralDiffuseBelowCanopyDirect,  & ! intent(out): down dif flux below veg layer (per unit in flux), (1:nBands)
                   scalarGproj,                       & ! intent(out): projected leaf+stem area in solar direction
                   spectralCanopyReflectedDirect,     & ! intent(out): flux reflected by veg layer   (per unit incoming flux), (1:nBands)
                   spectralGroundReflectedDirect,     & ! intent(out): flux reflected by ground (per unit incoming flux), (1:nBands)
                   ! input-output
                   scalarBetweenCanopyGapFraction,    & ! intent(inout): between canopy gap fraction for beam (-)
                   scalarWithinCanopyGapFraction      ) ! intent(inout): within canopy gap fraction for beam (-)
  
    ic = 1
    ! two-stream approximation for diffuse radiation (from CLM/Noah-MP)
    call twoStream(&
                   ! input
                   iBand,                             & ! intent(in): waveband number
                   ic,                                & ! intent(in): 0=unit incoming direct; 1=unit incoming diffuse
                   vegTypeIndex,                      & ! intent(in): vegetation type
                   scalarCosZenith,                   & ! intent(in): cosine of direct zenith angle (0-1)
                   scalarExposedVAI,                  & ! intent(in): one-sided leaf+stem area index (m2/m2)
                   scalarCanopyWetFraction,           & ! intent(in): fraction of lai, sai that is wetted (-)
                   scalarCanopyTempTrial,             & ! intent(in): surface temperature (k)
                   spectralAlbGndDirect,              & ! intent(in): direct  albedo of underlying surface (1:nBands) (-)
                   spectralAlbGndDiffuse,             & ! intent(in): diffuse albedo of underlying surface (1:nBands) (-)
                   spectralVegReflc,                  & ! intent(in): leaf+stem reflectance (1:nbands)
                   spectralVegTrans,                  & ! intent(in): leaf+stem transmittance (1:nBands)
                   scalarVegFraction,                 & ! intent(in): vegetation fraction (=1 forces no canopy gaps and open areas in radiation routine)
                   ist,                               & ! intent(in): surface type
                   iLoc,jLoc,                         & ! intent(in): grid indices
                   ! output
                   spectralCanopyAbsorbedDiffuse,     & ! intent(out): flux abs by veg layer (per unit incoming flux), (1:nBands)
                   spectralTotalReflectedDiffuse,     & ! intent(out): flux refl above veg layer (per unit incoming flux), (1:nBands)
                   spectralDirectBelowCanopyDiffuse,  & ! intent(out): down dir flux below veg layer (per unit in flux), (1:nBands)
                   spectralDiffuseBelowCanopyDiffuse, & ! intent(out): down dif flux below veg layer (per unit in flux), (1:nBands)
                   scalarGproj,                       & ! intent(out): projected leaf+stem area in solar direction
                   spectralCanopyReflectedDiffuse,    & ! intent(out): flux reflected by veg layer   (per unit incoming flux), (1:nBands)
                   spectralGroundReflectedDiffuse,    & ! intent(out): flux reflected by ground (per unit incoming flux), (1:nBands)
                   ! input-output
                   scalarBetweenCanopyGapFraction,    & ! intent(inout): between canopy gap fraction for beam (-)
                   scalarWithinCanopyGapFraction      ) ! intent(inout): within canopy gap fraction for beam (-)


    ! compute below-canopy radiation
    spectralBelowCanopyDirect(iBand)  = spectralIncomingDirect(iBand)*spectralDirectBelowCanopyDirect(iBand)      ! direct radiation
    spectralBelowCanopyDiffuse(iBand) = spectralIncomingDirect(iBand)*spectralDiffuseBelowCanopyDirect(iBand) + & ! direct radiation transmitted as diffuse
                                        spectralIncomingDiffuse(iBand)*spectralDiffuseBelowCanopyDiffuse(iBand)   ! diffuse radiation transmitted as diffuse
 
    ! accumulate radiation transmitted below the canopy (W m-2)
    scalarBelowCanopySolar    = scalarBelowCanopySolar + &                                                  ! contribution from all previous wave bands
                                spectralBelowCanopyDirect(iBand) + spectralBelowCanopyDiffuse(iBand)        ! contribution from current wave band

    ! accumulate radiation absorbed by the vegetation canopy (W m-2)
    scalarCanopyAbsorbedSolar = scalarCanopyAbsorbedSolar + &                                               ! contribution from all previous wave bands
                                spectralIncomingDirect(iBand)*spectralCanopyAbsorbedDirect(iBand) + &       ! direct radiation from current wave band
                                spectralIncomingDiffuse(iBand)*spectralCanopyAbsorbedDiffuse(iBand)         ! diffuse radiation from current wave band

    ! accumulate radiation absorbed by the ground (W m-2)
    scalarGroundAbsorbedSolar = scalarGroundAbsorbedSolar + &                                               ! contribution from all previous wave bands
                                spectralBelowCanopyDirect(iBand)*(1._dp - spectralAlbGndDirect(iBand)) + &  ! direct radiation from current wave band
                                spectralBelowCanopyDiffuse(iBand)*(1._dp - spectralAlbGndDiffuse(iBand))    ! diffuse radiation from current wave band

    ! save canopy radiation absorbed in visible wavelengths
    ! NOTE: here flux is per unit incoming flux
    if(iBand == ixVisible)then
     visibleAbsDirect  = spectralIncomingDirect(ixVisible)*spectralCanopyAbsorbedDirect(ixVisible)
     visibleAbsDiffuse = spectralIncomingDiffuse(ixVisible)*spectralCanopyAbsorbedDiffuse(ixVisible)
    endif

   end do  ! (looping through wave bands)

  ! -----------------------------------------------------------------------------------------------------------------------------------------------------------
  case default; err=20; message=trim(message)//'unable to identify option for canopy sw radiation'; return

 end select ! (option for canopy sw radiation)

 
 ! ============================================================================================================================================================
 ! ============================================================================================================================================================

 ! compute variables used in photosynthesis routines

 ! compute sunlit fraction of canopy (from CLM/Noah-MP)
 ext = scalarGproj/scalarCosZenith  ! optical depth of direct beam per unit leaf + stem area
 scalarCanopySunlitFraction = (1._dp - exp(-ext*scalarExposedVAI)) / max(ext*scalarExposedVAI,mpe)
 if(scalarCanopySunlitFraction < 0.01_dp) scalarCanopySunlitFraction = 0._dp

 ! compute sunlit and shaded LAI
 scalarCanopyShadedFraction = 1._dp - scalarCanopySunlitFraction
 scalarCanopySunlitLAI      = scalarExposedLAI*scalarCanopySunlitFraction
 scalarCanopyShadedLAI      = scalarExposedLAI*scalarCanopyShadedFraction

 ! compute PAR for sunlit and shaded leaves (from CLM/Noah-MP)
 fractionLAI       = scalarExposedLAI / max(scalarExposedVAI, mpe)
 if(scalarCanopySunlitFraction > tiny(scalarCanopySunlitFraction))then
  scalarCanopySunlitPAR = (visibleAbsDirect + scalarCanopySunlitFraction*visibleAbsDiffuse) * fractionLAI / max(scalarCanopySunlitLAI, mpe)
  scalarCanopyShadedPAR = (                   scalarCanopyShadedFraction*visibleAbsDiffuse) * fractionLAI / max(scalarCanopyShadedLAI, mpe)
 else
  scalarCanopySunlitPAR = 0._dp
  scalarCanopyShadedPAR = (visibleAbsDirect + visibleAbsDiffuse) * fractionLAI / max(scalarCanopyShadedLAI, mpe)
 endif
 !print*, 'scalarCanopySunlitLAI, fractionLAI, visibleAbsDirect, visibleAbsDiffuse, scalarCanopySunlitPAR = ', &
 !         scalarCanopySunlitLAI, fractionLAI, visibleAbsDirect, visibleAbsDiffuse, scalarCanopySunlitPAR


 
 end subroutine vegSWavRad


 ! *************************************************************************************************************************************
 ! ***** PRIVATE SUBROUTINE: gndAlbedo: compute the albedo of the ground surface
 ! *************************************************************************************************************************************
 subroutine gndAlbedo(&
                      ! input
                      soilTypeIndex,                         & ! intent(in): index of soil type
                      scalarGroundSnowFraction,              & ! intent(in): fraction of ground that is snow covered (-)
                      scalarVolFracLiqUpper,                 & ! intent(in): volumetric liquid water content in upper-most soil layer (-)
                      spectralSnowAlbedoDirect,              & ! intent(in): direct albedo of snow in each spectral band (-)
                      spectralSnowAlbedoDiffuse,             & ! intent(in): diffuse albedo of snow in each spectral band (-)
                      ! output
                      spectralAlbGndDirect,                  & ! intent(out): direct  albedo of underlying surface (-)
                      spectralAlbGndDiffuse,                 & ! intent(out): diffuse albedo of underlying surface (-)
                      err,message)                             ! intent(out): error control
 ! --------------------------------------------------------------------------------------------------------------------------------------
 ! identify parameters for soil albedo
 USE NOAHMP_RAD_PARAMETERS, only: ALBSAT,ALBDRY  ! Noah-MP: saturated and dry soil albedos for each wave band
 ! --------------------------------------------------------------------------------------------------------------------------------------
 ! input: model control
 integer(i4b),intent(in)        :: soilTypeIndex                ! index of soil type
 real(dp),intent(in)            :: scalarGroundSnowFraction     ! fraction of ground that is snow covered (-)
 real(dp),intent(in)            :: scalarVolFracLiqUpper        ! volumetric liquid water content in upper-most soil layer (-)
 real(dp),intent(in)            :: spectralSnowAlbedoDirect(:)  ! direct albedo of snow in each spectral band (-)
 real(dp),intent(in)            :: spectralSnowAlbedoDiffuse(:) ! diffuse albedo of snow in each spectral band (-)
 ! output
 real(dp),intent(out)           :: spectralAlbGndDirect(:)      ! direct  albedo of underlying surface (-)
 real(dp),intent(out)           :: spectralAlbGndDiffuse(:)     ! diffuse albedo of underlying surface (-)
 integer(i4b),intent(out)       :: err                          ! error code
 character(*),intent(out)       :: message                      ! error message
 ! local variables
 integer(i4b)                   :: iBand                        ! index of spectral band
 real(dp)                       :: xInc                         ! soil water correction factor for soil albedo
 real(dp),dimension(1:nBands)   :: spectralSoilAlbedo           ! soil albedo in each spectral band
 ! initialize error control
 err=0; message='gndAlbedo/'

 ! compute soil albedo
 do iBand=1,nBands   ! loop through spectral bands
  xInc = max(0.11_dp - 0.40_dp*scalarVolFracLiqUpper, 0._dp)
  spectralSoilAlbedo(iBand)  = min(ALBSAT(soilTypeIndex,iBand)+xInc,ALBDRY(soilTypeIndex,iBand))
 end do  ! (looping through spectral bands)

 ! compute surface albedo (weighted combination of snow and soil)
 do iBand=1,nBands
  spectralAlbGndDirect(iBand)  = (1._dp - scalarGroundSnowFraction)*spectralSoilAlbedo(iBand)  + scalarGroundSnowFraction*spectralSnowAlbedoDirect(iBand)
  spectralAlbGndDiffuse(iBand) = (1._dp - scalarGroundSnowFraction)*spectralSoilAlbedo(iBand)  + scalarGroundSnowFraction*spectralSnowAlbedoDiffuse(iBand)
 end do  ! (looping through spectral bands)

 end subroutine gndAlbedo


end module vegSWavRad_module
