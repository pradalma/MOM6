module ISOMIP_initialization
!***********************************************************************
!*                   GNU General Public License                        *
!* This file is a part of MOM.                                         *
!*                                                                     *
!* MOM is free software; you can redistribute it and/or modify it and  *
!* are expected to follow the terms of the GNU General Public License  *
!* as published by the Free Software Foundation; either version 2 of   *
!* the License, or (at your option) any later version.                 *
!*                                                                     *
!* MOM is distributed in the hope that it will be useful, but WITHOUT  *
!* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY  *
!* or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public    *
!* License for more details.                                           *
!*                                                                     *
!* For the full text of the GNU General Public License,                *
!* write to: Free Software Foundation, Inc.,                           *
!*           675 Mass Ave, Cambridge, MA 02139, USA.                   *
!* or see:   http://www.gnu.org/licenses/gpl.html                      *
!***********************************************************************

use MOM_ALE_sponge, only : ALE_sponge_CS, set_up_ALE_sponge_field, initialize_ALE_sponge
use MOM_dyn_horgrid, only : dyn_horgrid_type
use MOM_error_handler, only : MOM_mesg, MOM_error, FATAL, is_root_pe, WARNING
use MOM_file_parser, only : get_param, log_version, param_file_type
use MOM_get_input, only : directories
use MOM_grid, only : ocean_grid_type
use MOM_io, only : close_file, fieldtype, file_exists
use MOM_io, only : open_file, read_data, read_axis_data, SINGLE_FILE
use MOM_io, only : write_field, slasher, vardesc
use MOM_variables, only : thermo_var_ptrs
use MOM_verticalGrid, only : verticalGrid_type
use MOM_EOS, only : calculate_density, calculate_density_derivs, EOS_type
use regrid_consts, only : coordinateMode, DEFAULT_COORDINATE_MODE
use regrid_consts, only : REGRIDDING_LAYER, REGRIDDING_ZSTAR
use regrid_consts, only : REGRIDDING_RHO, REGRIDDING_SIGMA
implicit none ; private

#include <MOM_memory.h>

! -----------------------------------------------------------------------------
! Private (module-wise) parameters
! -----------------------------------------------------------------------------

character(len=40) :: mod = "ISOMIP_initialization" ! This module's name.

! -----------------------------------------------------------------------------
! The following routines are visible to the outside world
! -----------------------------------------------------------------------------
public ISOMIP_initialize_topography
public ISOMIP_initialize_thickness
public ISOMIP_initialize_temperature_salinity 
public ISOMIP_initialize_sponges

! -----------------------------------------------------------------------------
! This module contains the following routines
! -----------------------------------------------------------------------------
contains

!> Initialization of topography
subroutine ISOMIP_initialize_topography(D, G, param_file, max_depth)
  type(dyn_horgrid_type),             intent(in)  :: G !< The dynamic horizontal grid type
  real, dimension(G%isd:G%ied,G%jsd:G%jed), &
                                      intent(out) :: D !< Ocean bottom depth in m
  type(param_file_type),              intent(in)  :: param_file !< Parameter file structure
  real,                               intent(in)  :: max_depth  !< Maximum depth of model in m

! This subroutine sets up the ISOMIP topography
  real :: min_depth ! The minimum and maximum depths in m.

! The following variables are used to set up the bathymetry in the ISOMIP example.
! check this paper: http://www.geosci-model-dev-discuss.net/8/9859/2015/gmdd-8-9859-2015.pdf

  real :: bmax            ! max depth of bedrock topography
  real :: b0,b2,b4,b6     ! first, second, third and fourth bedrock topography coeff
  real :: xbar           ! characteristic along-flow lenght scale of the bedrock
  real :: dc              ! depth of the trough compared with side walls
  real :: fc              ! characteristic width of the side walls of the channel
  real :: wc              ! half-width of the trough
  real :: ly              ! domain width (across ice flow)
  real :: bx, by, xtil    ! dummy vatiables
  logical :: is_2D         ! If true, use 2D setup

! G%ieg and G%jeg are the last indices in the global domain
!  real, dimension (G%ieg) :: xtil    ! eq. 3
!  real, dimension (G%ieg) :: bx            ! eq. 2
!  real, dimension (G%ieg,G%jeg) :: dummy1            ! dummy array
!  real, dimension (G%jeg) :: by            ! eq. 4

! This include declares and sets the variable "version".
#include "version_variable.h"
  character(len=40)  :: mod = "ISOMIP_initialize_topography" ! This subroutine's name.
  integer :: i, j, is, ie, js, je, isd, ied, jsd, jed
  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec
  isd = G%isd ; ied = G%ied ; jsd = G%jsd ; jed = G%jed
 

  call MOM_mesg("  ISOMIP_initialization.F90, ISOMIP_initialize_topography: setting topography", 5)

  call log_version(param_file, mod, version, "")
  call get_param(param_file, mod, "MINIMUM_DEPTH", min_depth, &
                 "The minimum depth of the ocean.", units="m", default=0.0)
  call get_param(param_file, mod, "ISOMIP_2D",is_2D,'If true, use a 2D setup.', default=.false.)

! The following variables should be transformed into runtime parameters?
  bmax=720.0; b0=-150.0; b2=-728.8; b4=343.91; b6=-50.57
  xbar=300.0E3; dc=500.0; fc=4.0E3; wc=24.0E3; ly=80.0E3
  bx = 0.0; by = 0.0; xtil = 0.0


  if (is_2D) then
    do j=js,je ; do i=is,ie
      ! 2D setup
      xtil = G%geoLonT(i,j)*1.0e3/xbar 
      !xtil = 450*1.0e3/xbar
      bx = b0+b2*xtil**2 + b4*xtil**4 + b6*xtil**6
      !by = (dc/(1.+exp(-2.*(G%geoLatT(i,j)*1.0e3- ly/2. - wc)/fc))) + &
      !        (dc/(1.+exp(2.*(G%geoLatT(i,j)*1.0e3- ly/2. + wc)/fc)))

      by = (dc/(1.+exp(-2.*(20.*1.0e3- ly/2. - wc)/fc))) + &
           (dc/(1.+exp(2.*(20.*1.0e3- ly/2. + wc)/fc)))  

      D(i,j) = -max(bx+by,-bmax)
      if (D(i,j) > max_depth) D(i,j) = max_depth
      if (D(i,j) < min_depth) D(i,j) = 0.5*min_depth
    enddo ; enddo

  else 
    do j=js,je ; do i=is,ie
      ! 3D         
      xtil = G%geoLonT(i,j)*1.0e3/xbar
      bx = b0+b2*xtil**2 + b4*xtil**4 + b6*xtil**6
      by = (dc/(1.+exp(-2.*(G%geoLatT(i,j)*1.0e3- ly/2. - wc)/fc))) + &
              (dc/(1.+exp(2.*(G%geoLatT(i,j)*1.0e3- ly/2. + wc)/fc)))

      D(i,j) = -max(bx+by,-bmax)
      if (D(i,j) > max_depth) D(i,j) = max_depth
      if (D(i,j) < min_depth) D(i,j) = 0.5*min_depth
    enddo ; enddo
  endif

end subroutine ISOMIP_initialize_topography
! -----------------------------------------------------------------------------

!> Initialization of thicknesses
subroutine ISOMIP_initialize_thickness ( h, G, GV, param_file, tv )
  type(ocean_grid_type), intent(in) :: G                !< The ocean's grid structure.
  type(verticalGrid_type), intent(in) :: GV             !< The ocean's vertical grid structure.
  real, intent(out), dimension(SZI_(G),SZJ_(G),SZK_(GV)) :: h !< The thickness that is being
                                                        !! initialized.
  type(param_file_type), intent(in) :: param_file       !< A structure indicating the
                                                        !! open file to parse for model
                                                        !! parameter values.
  type(thermo_var_ptrs), intent(in) :: tv               !< A structure containing pointers
                                                        !! to any available thermodynamic
                                                        !! fields, including eq. of state.
  ! Local variables
  real :: e0(SZK_(G)+1)     ! The resting interface heights, in m, usually !
                          ! negative because it is positive upward.      !
  real :: eta1D(SZK_(G)+1)! Interface height relative to the sea surface !
                          ! positive upward, in m.                       !
  integer :: i, j, k, is, ie, js, je, nz, tmp1
  real    :: x
  real    :: delta_h, rho_range
  real    :: min_thickness, s_sur, s_bot, t_sur, t_bot, rho_sur, rho_bot
  character(len=40) :: verticalCoordinate

  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = G%ke

  call MOM_mesg("MOM_initialization.F90, initialize_thickness_uniform: setting thickness")

  call get_param(param_file,mod,"MIN_THICKNESS",min_thickness,'Minimum layer thickness',units='m',default=1.e-3)
  call get_param(param_file,mod,"REGRIDDING_COORDINATE_MODE", verticalCoordinate, &
            default=DEFAULT_COORDINATE_MODE)
 
  select case ( coordinateMode(verticalCoordinate) )
    
  case ( REGRIDDING_LAYER, REGRIDDING_RHO ) ! Initial thicknesses for isopycnal coordinates
    call get_param(param_file, mod, "ISOMIP_T_SUR",t_sur,'Temperature at the surface (interface)', default=-1.9)
    call get_param(param_file, mod, "ISOMIP_S_SUR", s_sur, 'Salinity at the surface (interface)',  default=33.8)
    call get_param(param_file, mod, "ISOMIP_T_BOT", t_bot, 'Temperature at the bottom (interface)', default=-1.9)
    call get_param(param_file, mod, "ISOMIP_S_BOT", s_bot,'Salinity at the bottom (interface)', default=34.55)

    ! Compute min/max density using T_SUR/S_SUR and T_BOT/S_BOT
    call calculate_density(t_sur,s_sur,0.0,rho_sur,tv%eqn_of_state)
    !write (*,*)'Surface density is:', rho_sur
    call calculate_density(t_bot,s_bot,0.0,rho_bot,tv%eqn_of_state)
    !write (*,*)'Bottom density is:', rho_bot
    rho_range = rho_bot - rho_sur
    !write (*,*)'Density range is:', rho_range
 
    ! Construct notional interface positions
    e0(1) = 0.
    do K=2,nz
      e0(k) = -G%max_depth * ( 0.5 * ( GV%Rlay(k-1) + GV%Rlay(k) ) - rho_sur ) / rho_range
      e0(k) = min( 0., e0(k) ) ! Bound by surface
      e0(k) = max( -G%max_depth, e0(k) ) ! Bound by possible deepest point in model
      !write(*,*)'G%max_depth,GV%Rlay(k-1),GV%Rlay(k),e0(k)',G%max_depth,GV%Rlay(k-1),GV%Rlay(k),e0(k)  
  
    enddo
    e0(nz+1) = -G%max_depth
    
    ! Calculate thicknesses
    do j=js,je ; do i=is,ie
      eta1D(nz+1) = -1.0*G%bathyT(i,j)
      do k=nz,1,-1
        eta1D(k) = e0(k)
        if (eta1D(k) < (eta1D(k+1) + GV%Angstrom_z)) then
          eta1D(k) = eta1D(k+1) + GV%Angstrom_z
          h(i,j,k) = GV%Angstrom_z
        else
          h(i,j,k) = eta1D(k) - eta1D(k+1)
        endif
      enddo
    enddo ; enddo

  case ( REGRIDDING_ZSTAR )                       ! Initial thicknesses for z coordinates
    do j=js,je ; do i=is,ie
      eta1D(nz+1) = -1.0*G%bathyT(i,j)
      do k=nz,1,-1
        eta1D(k) =  -G%max_depth * real(k-1) / real(nz)
        if (eta1D(k) < (eta1D(k+1) + min_thickness)) then
          eta1D(k) = eta1D(k+1) + min_thickness
          h(i,j,k) = min_thickness
        else
          h(i,j,k) = eta1D(k) - eta1D(k+1)
        endif
      enddo
   enddo ; enddo

  case ( REGRIDDING_SIGMA )             ! Initial thicknesses for sigma coordinates
    do j=js,je ; do i=is,ie
      delta_h = G%bathyT(i,j) / dfloat(nz)
      h(i,j,:) = delta_h
    end do ; end do 

  case default
      call MOM_error(FATAL,"isomip_initialize: "// &
      "Unrecognized i.c. setup - set REGRIDDING_COORDINATE_MODE")

  end select

end subroutine ISOMIP_initialize_thickness

!> Initial values for temperature and salinity
subroutine ISOMIP_initialize_temperature_salinity ( T, S, h, G, GV, param_file, &
                                                    eqn_of_state)
  type(ocean_grid_type),                     intent(in)  :: G !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)  :: GV !< Vertical grid structure
  real, dimension(SZI_(G),SZJ_(G), SZK_(G)), intent(out) :: T !< Potential temperature (degC)
  real, dimension(SZI_(G),SZJ_(G), SZK_(G)), intent(out) :: S !< Salinity (ppt)
  real, dimension(SZI_(G),SZJ_(G), SZK_(G)), intent(in)  :: h !< Layer thickness (m or Pa)
  type(param_file_type),                     intent(in)  :: param_file !< Parameter file structure
  type(EOS_type),                            pointer     :: eqn_of_state !< Equation of state structure
  ! Local variables

  integer   :: i, j, k, is, ie, js, je, nz
  real      :: x, ds, dt, rho_sur, rho_bot
  real      :: xi0, xi1, dxi, r, S_sur, T_sur, S_bot, T_bot, S_range, T_range
  real      :: z          ! vertical position in z space
  character(len=40) :: verticalCoordinate, density_profile
  real :: rho_tmp
  
  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = G%ke

  call get_param(param_file,mod,"REGRIDDING_COORDINATE_MODE", verticalCoordinate, &
            default=DEFAULT_COORDINATE_MODE)
  call get_param(param_file, mod, "ISOMIP_T_SUR",t_sur,'Temperature at the surface (interface)', default=-1.9,&
                 do_not_log=.true.)
  call get_param(param_file, mod, "ISOMIP_S_SUR", s_sur, 'Salinity at the surface (interface)',  default=33.8,&
                 do_not_log=.true.)
  call get_param(param_file, mod, "ISOMIP_T_BOT", t_bot, 'Temperature at the bottom (interface)', default=-1.9,&
                 do_not_log=.true.)
  call get_param(param_file, mod, "ISOMIP_S_BOT", s_bot,'Salinity at the bottom (interface)', default=34.55,&
                 do_not_log=.true.)

  call calculate_density(t_sur,s_sur,0.0,rho_sur,eqn_of_state)
  !write (*,*)'Density in the surface layer:', rho_sur
  call calculate_density(t_bot,s_bot,0.0,rho_bot,eqn_of_state)
  !write (*,*)'Density in the bottom layer::', rho_bot

  S_range = s_sur - s_bot
  T_range = t_sur - t_bot

  select case ( coordinateMode(verticalCoordinate) )

    case (  REGRIDDING_RHO, REGRIDDING_ZSTAR, REGRIDDING_SIGMA )
      S_range = S_range / G%max_depth ! Convert S_range into dS/dz
      T_range = T_range / G%max_depth ! Convert T_range into dT/dz
      do j=js,je ; do i=is,ie
        xi0 = -G%bathyT(i,j);
        do k = nz,1,-1
          xi0 = xi0 + 0.5 * h(i,j,k) ! Depth in middle of layer
          S(i,j,k) = S_sur + S_range * xi0
          T(i,j,k) = T_sur + T_range * xi0
          xi0 = xi0 + 0.5 * h(i,j,k) ! Depth at top of layer
        enddo
      enddo ; enddo

!i=G%iec; j=G%jec
!do k = 1,nz
!  call calculate_density(T(i,j,k),S(i,j,k),0.0,rho_tmp,eqn_of_state)
!  !write(*,*) 'k,h,T,S,rho,Rlay',k,h(i,j,k),T(i,j,k),S(i,j,k),rho_tmp,GV%Rlay(k)
!enddo

!   case ( REGRIDDING_ZSTAR, REGRIDDING_SIGMA )
!
!      do j=js,je ; do i=is,ie
!        xi0 = 0.0;
!        do k = 1,nz
!          xi1 = xi0 + h(i,j,k) / G%max_depth;
!          S(i,j,k) = S_sur + 0.5 * S_range * (xi0 + xi1);
!          T(i,j,k) = T_sur + 0.5 * T_range * (xi0 + xi1);
!          xi0 = xi1;
!        enddo
!      enddo ; enddo
    
   case default
      call MOM_error(FATAL,"isomip_initialize: "// &
      "Unrecognized i.c. setup - set REGRIDDING_COORDINATE_MODE")

  end select

end subroutine ISOMIP_initialize_temperature_salinity

!> Sets up the the inverse restoration time (Idamp), and
! the values towards which the interface heights and an arbitrary
! number of tracers should be restored within each sponge.
subroutine ISOMIP_initialize_sponges(G,GV, tv, PF, CSp)
  type(ocean_grid_type), intent(in) :: G    !< The ocean's grid structure.
  type(verticalGrid_type), intent(in) :: GV !< The ocean's vertical grid structure.
  type(thermo_var_ptrs), intent(in) :: tv   !< A structure containing pointers
                                            !! to any available thermodynamic
                                            !! fields, potential temperature and
                                            !! salinity or mixed layer density.
                                            !! Absent fields have NULL ptrs.
  type(param_file_type), intent(in) :: PF   !< A structure indicating the
                                            !! open file to parse for model
                                            !! parameter values.
  type(ALE_sponge_CS),   pointer    :: CSp  !< A pointer that is set to point to
                                            !! the control structure for this module.
  ! Local variables
  real :: T(SZI_(G),SZJ_(G),SZK_(G))  ! A temporary array for temp 
  real :: S(SZI_(G),SZJ_(G),SZK_(G))  ! A temporary array for salt
  real :: RHO(SZI_(G),SZJ_(G),SZK_(G))  ! A temporary array for RHO
  real :: h(SZI_(G),SZJ_(G),SZK_(G))  ! A temporary array for thickness
  real :: Idamp(SZI_(G),SZJ_(G))    ! The inverse damping rate, in s-1.
  real :: TNUDG                     ! Nudging time scale, days
  real      :: S_sur, T_sur;        ! Surface salinity and temerature in sponge
  real      :: S_bot, T_bot;        ! Bottom salinity and temerature in sponge 
  real      :: t_ref, s_ref         ! reference T and S
  real      :: rho_sur, rho_bot, rho_range, t_range, s_range

  real :: e0(SZK_(G))               ! The resting interface heights, in m, usually !
                                    ! negative because it is positive upward.      !
  real :: eta1D(SZK_(G)+1)          ! Interface height relative to the sea surface !
                                    ! positive upward, in m.
  real :: min_depth, dummy1, z, delta_h
  real :: damp, rho_dummy, min_thickness, rho_tmp, xi0
  character(len=40) :: verticalCoordinate

  character(len=40)  :: mod = "ISOMIP_initialize_sponges" ! This subroutine's name.
  integer :: i, j, k, is, ie, js, je, isd, ied, jsd, jed, nz

  is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = G%ke
  isd = G%isd ; ied = G%ied ; jsd = G%jsd ; jed = G%jed

  call get_param(PF,mod,"MIN_THICKNESS",min_thickness,'Minimum layer thickness',units='m',default=1.e-3)

  call get_param(PF,mod,"REGRIDDING_COORDINATE_MODE", verticalCoordinate, &
            default=DEFAULT_COORDINATE_MODE)

  call get_param(PF, mod, "ISOMIP_TNUDG", TNUDG, 'Nudging time scale for sponge layers (days)',  default=0.0)

  call get_param(PF, mod, "T_REF", t_ref, 'Reference temperature',  default=10.0,&
                 do_not_log=.true.)

  call get_param(PF, mod, "S_REF", s_ref, 'Reference salinity',  default=35.0,&
                 do_not_log=.true.)

  call get_param(PF, mod, "ISOMIP_S_SUR_SPONGE", s_sur, 'Surface salinity in sponge layer.',  default=s_ref)
  
  call get_param(PF, mod, "ISOMIP_S_BOT_SPONGE", s_bot, 'Bottom salinity in sponge layer.',  default=s_ref)
 
  call get_param(PF, mod, "ISOMIP_T_SUR_SPONGE", t_sur, 'Surface temperature in sponge layer.',  default=t_ref)
  
  call get_param(PF, mod, "ISOMIP_T_BOT_SPONGE", t_bot, 'Bottom temperature in sponge layer.',  default=t_ref)

  T(:,:,:) = 0.0 ; S(:,:,:) = 0.0 ; Idamp(:,:) = 0.0; RHO(:,:,:) = 0.0
  S_range = s_sur - s_bot
  T_range = t_sur - t_bot

!   Set up sponges for ISOMIP configuration
  call get_param(PF, mod, "MINIMUM_DEPTH", min_depth, &
                 "The minimum depth of the ocean.", units="m", default=0.0)

   
  select case ( coordinateMode(verticalCoordinate) )

  case ( REGRIDDING_LAYER, REGRIDDING_RHO ) 
    ! Compute min/max density using T_SUR/S_SUR and T_BOT/S_BOT
    call calculate_density(t_sur,s_sur,0.0,rho_sur,tv%eqn_of_state)
    !write (*,*)'Surface density in sponge:', rho_sur
    call calculate_density(t_bot,s_bot,0.0,rho_bot,tv%eqn_of_state)
    !write (*,*)'Bottom density in sponge:', rho_bot
    rho_range = rho_bot - rho_sur
    !write (*,*)'Density range in sponge:', rho_range

    ! Construct notional interface positions
    e0(1) = 0.
    do K=2,nz
      e0(k) = -G%max_depth * ( 0.5 * ( GV%Rlay(k-1) + GV%Rlay(k) ) - rho_sur ) / rho_range
      e0(k) = min( 0., e0(k) ) ! Bound by surface
      e0(k) = max( -G%max_depth, e0(k) ) ! Bound by possible deepest point in model
      !write(*,*)'G%max_depth,GV%Rlay(k-1),GV%Rlay(k),e0(k)',G%max_depth,GV%Rlay(k-1),GV%Rlay(k),e0(k)  

    enddo
    e0(nz+1) = -G%max_depth

    ! Calculate thicknesses
    do j=js,je ; do i=is,ie
      eta1D(nz+1) = -1.0*G%bathyT(i,j)
      do k=nz,1,-1
        eta1D(k) = e0(k)
        if (eta1D(k) < (eta1D(k+1) + GV%Angstrom_z)) then
          eta1D(k) = eta1D(k+1) + GV%Angstrom_z
          h(i,j,k) = GV%Angstrom_z
        else
          h(i,j,k) = eta1D(k) - eta1D(k+1)
        endif
      enddo
    enddo ; enddo

  case ( REGRIDDING_ZSTAR )                       ! Initial thicknesses for z coordinates
    do j=js,je ; do i=is,ie
      eta1D(nz+1) = -1.0*G%bathyT(i,j)
      do k=nz,1,-1
        eta1D(k) =  -G%max_depth * real(k-1) / real(nz)
        if (eta1D(k) < (eta1D(k+1) + min_thickness)) then
          eta1D(k) = eta1D(k+1) + min_thickness
          h(i,j,k) = min_thickness
        else
          h(i,j,k) = eta1D(k) - eta1D(k+1)
        endif
      enddo
   enddo ; enddo

   case ( REGRIDDING_SIGMA )             ! Initial thicknesses for sigma coordinates
    do j=js,je ; do i=is,ie
      delta_h = G%bathyT(i,j) / dfloat(nz)
      h(i,j,:) = delta_h
    end do ; end do

  case default
      call MOM_error(FATAL,"ISOMIP_initialize_sponges: "// &
      "Unrecognized i.c. setup - set REGRIDDING_COORDINATE_MODE")

  end select

!  Here the inverse damping time, in s-1, is set. Set Idamp to 0     !
!  wherever there is no sponge, and the subroutines that are called  !
!  will automatically set up the sponges only where Idamp is positive!
!  and mask2dT is 1.  

   do i=is,ie; do j=js,je
      if (G%geoLonT(i,j) >= 790.0 .AND. G%geoLonT(i,j) <= 800.0) then

! 1 / day
        dummy1=(G%geoLonT(i,j)-790.0)/(800.0-790.0)
        damp = 1.0/TNUDG * max(0.0,dummy1)

      else ; damp=0.0
      endif

! convert to 1 / seconds
      if (G%bathyT(i,j) > min_depth) then
          Idamp(i,j) = damp/86400.0
      else ; Idamp(i,j) = 0.0 ; endif
   

   enddo ; enddo

   if (associated(CSp)) then
    call MOM_error(WARNING, "ISOMIP_initialize_sponges called with an associated "// &
                            "control structure.")
    return
  endif

!  This call sets up the damping rates and interface heights.
!  This sets the inverse damping timescale fields in the sponges.    !

  call initialize_ALE_sponge(Idamp,h, nz, G, PF, CSp)

! setup temp and salt at the sponge zone
  select case ( coordinateMode(verticalCoordinate) )

    case (  REGRIDDING_SIGMA, REGRIDDING_ZSTAR, REGRIDDING_RHO )
      S_range = S_range / G%max_depth ! Convert S_range into dS/dz
      T_range = T_range / G%max_depth ! Convert T_range into dT/dz
      do j=js,je ; do i=is,ie
        xi0 = -G%bathyT(i,j);
        do k = nz,1,-1
          xi0 = xi0 + 0.5 * h(i,j,k) ! Depth in middle of layer
          S(i,j,k) = S_sur + S_range * xi0
          T(i,j,k) = T_sur + T_range * xi0
          xi0 = xi0 + 0.5 * h(i,j,k) ! Depth at top of layer
        enddo
      enddo ; enddo
  i=G%iec; j=G%jec
  do k = 1,nz
    call calculate_density(T(i,j,k),S(i,j,k),0.0,rho_tmp,tv%eqn_of_state)
    !write(*,*) 'Sponge - k,h,T,S,rho,Rlay',k,h(i,j,k),T(i,j,k),S(i,j,k),rho_tmp,GV%Rlay(k)
  enddo

   case default
      call MOM_error(FATAL,"isomip_initialize_sponge: "// &
      "Unrecognized i.c. setup - set REGRIDDING_COORDINATE_MODE")

  end select


!   Now register all of the fields which are damped in the sponge.   !
! By default, momentum is advected vertically within the sponge, but !
! momentum is typically not damped within the sponge.                !

!  The remaining calls to set_up_sponge_field can be in any order. !
  if ( associated(tv%T) ) then
      call set_up_ALE_sponge_field(T,G,tv%T,CSp)
  endif

  if ( associated(tv%S) ) then
    call set_up_ALE_sponge_field(S,G,tv%S,CSp)
  endif


end subroutine ISOMIP_initialize_sponges

!> \class ISOMIP_initialization
!!
!!  The module configures the ISOMIP test case.
end module ISOMIP_initialization
