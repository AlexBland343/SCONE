module simpleGrid_class

  use numPrecision
  use universalVariables,    only : SURF_TOL, P_PHOTON_MG
  use genericProcedures,     only : fatalError, numToChar
  use dictionary_class,      only : dictionary
  use geometry_inter,        only : geometry
  use dynArray_class,        only : dynIntArray
  use nuclearDatabase_inter, only : nuclearDatabase
  use particle_class,        only : particle

  use geometryReg_mod,            only : gr_geomPtr => geomPtr
  use nuclearDataReg_mod,         only : ndReg_get => get

  !!
  !!
  !!
  type, private :: gridCell
    integer(shortInt), dimension(:), allocatable :: mats
    real(defReal)                                :: majorant

  end type gridCell

  !!
  !! As in latUniverse_class, idx is 1 in bottom X, Y & Z corner.
  !! It increases first with X then Y and lastly Z.
  !!
  !! sizeN  -> array [nx, ny, nz], the dimensions of the grid
  !! pitch  -> array [dx, dy, dz], the discretisation in each direction
  !! bounds -> [x_min, y_min, z_min, z_max, y_max, z_max] as in geometry_inter
  !!
  type, public :: simpleGrid
    class(geometry), pointer                     :: mainGeom => null()
    class(nuclearDatabase), pointer              :: xsData   => null()
    integer(shortInt), dimension(:), allocatable :: sizeN
    real(defReal), dimension(3)                  :: pitch = 0
    real(defReal), dimension(6)                  :: bounds
    real(defReal), dimension(3)                  :: corner
    real(defReal), dimension(3)                  :: a_bar
    type(gridCell), dimension(:), allocatable    :: gridCells

  contains
    procedure :: init
    !procedure :: kill
    procedure :: getDistance
    procedure :: getValue
    procedure :: storeMats
    procedure :: update
 
  end type simpleGrid

contains

  subroutine init(self, dict, geom, xsData)
    class(simpleGrid), intent(inout)             :: self
    class(dictionary), intent(in)                :: dict
    class(geometry), intent(in), pointer, optional         :: geom
    class(nuclearDatabase), intent(in), pointer, optional  :: xsData
    integer(shortInt)                            :: N
    integer(shortInt), dimension(:), allocatable :: searchN

    ! Store pointer to main geometry and data
!    self % mainGeom => geom
!    self % xsData   => xsData
    self % xsData => ndReg_get(P_PHOTON_MG) ! TODO: not an ideal way to do this but fine temporarily
    self % mainGeom => gr_geomPtr(1)  

    ! Store settings
    call dict % get(self % sizeN, 'dimensions')
    call dict % get(searchN, 'searchN')

    ! Get bounds of grid and calculate discretisations
    self % bounds = self % mainGeom % bounds()

    self % pitch(1)  = (self % bounds(4) - self % bounds(1)) / self % sizeN(1)
    self % pitch(2)  = (self % bounds(5) - self % bounds(2)) / self % sizeN(2)
    self % pitch(3)  = (self % bounds(6) - self % bounds(3)) / self % sizeN(3)

    self % corner = [self % bounds(1), self % bounds(2), self % bounds(3)]
    self % a_bar  = self % pitch * HALF - SURF_TOL

    ! Allocate space for cells
    N = self % sizeN(1) * self % sizeN(2) * self % sizeN(3)
    allocate(self % gridCells(N))

    ! Find material idxs present in each cell
    call self % storeMats(searchN)

  end subroutine init


  !!
  !! May have issues with non-box geometry root universe surface with reflective boundary
  !!
  function getDistance(self, r, u) result(dist)
    class(simpleGrid), intent(in)           :: self
    real(defReal), dimension(3), intent(in) :: r
    real(defReal), dimension(3), intent(in) :: u
    real(defReal)                           :: dist
    real(defReal), dimension(3)             :: r_bar, low, high !, point, corner, ratio
    character(100), parameter :: Here = 'getDistance (simpleGrid_class.f90)'

    ! Calculate position from grid corner
    r_bar = r - self % corner
    if (any(r_bar < -SURF_TOL)) call fatalError(Here, 'Point is outside grid geometry') !TODO only checks bottom for now

    ! Write as a fraction across cell
    r_bar = r_bar / self % pitch
    r_bar = r_bar - floor(r_bar)

    ! Account for surface tolerance
    low = SURF_TOL / self % pitch
    high = ONE - low
    do i = 1, 3
      if (r_bar(i) < low(i)  .and. u(i) < ZERO) r_bar(i) = ONE
      if (r_bar(i) > high(i) .and. u(i) > ZERO) r_bar(i) = ZERO
    end do

    ! Distance to centre plus distance from centre to required boundary
    r_bar = (HALF - r_bar + sign(HALF, u)) * self % pitch
    dist = minval(r_bar / u)

    if (dist <= ZERO) call fatalError(Here, 'Distance invalid: '//numToChar(dist))

    ! Increase by surface tolerance to ensure that boundary conditions are correctly applied
    dist = dist + SURF_TOL


    ! Round each dimension either up or down depending on which boundary will be hit
!    do i = 1, 3
!      if (u(i) >= 0) then
!    ! Round each dimension either up or down depending on which boundary will be hit
!    do i = 1, 3
!      if (u(i) >= 0) then
!        corner(i) = ceiling(point(i))
!      else
!        corner(i) = floor(point(i))
!      end if
!      ! Adjust if starting position was on boundary
!      if (abs(corner(i) - point(i)) < SURF_TOL) then
!        corner(i) = corner(i) + sign(ONE, u(i))
!      end if
!    end do

!    ! Convert back to spatial coordinates - this is now the coordinates of the corner being travelled towards
!    corner = corner * self % pitch

!    ! Determine which axis boundary will be hit first
!    ratio = (corner - r_bar) / u

!    dist = minval(ratio)


  end function getDistance


  !!
  !! Returns value of grid cell at position
  !!
  function getValue(self, r, u) result(val)
    class(simpleGrid), intent(in)           :: self
    real(defReal), dimension(3), intent(in) :: r
    real(defReal), dimension(3), intent(in) :: u
    real(defReal)                           :: val
    real(defReal), dimension(3)             :: r_bar
    integer(shortInt), dimension(3)         :: corner, ijk
    integer(shortInt)                       :: i, idx
    character(100), parameter :: Here = 'getValue (simpleGrid_class.f90)'

    ! Find lattice location in x,y&z
    ijk = floor((r - self % corner) / self % pitch) + 1

    ! Get position wrt middle of the lattice cell
    r_bar = r - self % corner - ijk * self % pitch + HALF * self % pitch

    ! Check if position is within surface tolerance
    ! If it is, push it to next cell
    do i = 1, 3
      if (abs(r_bar(i)) > self % a_bar(i) .and. r_bar(i)*u(i) > ZERO) then

        ! Select increment. Ternary expression
        if (u(i) < ZERO) then
          inc = -1
        else
          inc = 1
        end if

        ijk(i) = ijk(i) + inc

      end if
    end do

    ! Set localID & cellIdx
    if (any(ijk <= 0 .or. ijk > self % sizeN)) then ! Point is outside grid
      call fatalError(Here, 'Point is outside grid')

    else
      idx = ijk(1) + self % sizeN(1) * (ijk(2)-1 + self % sizeN(2) * (ijk(3)-1))

    end if



!    ! Get grid cell bottom corner
!    r_bar = reposition(r, self % bounds) - self % corner
!    corner = floor(r_bar)
!    do i = 1, 3
!      if (corner(i) == r_bar(i) .and. u(i) < 0) then
!        ! Adjust for point starting on cell boundary
!        corner(i) = corner(i) - 1
!      end if
!    end do
!
!    ! Adjust for bottom corner starting at 1
!    corner = corner + 1
!
!    ! Get grid cell idx
!    idx = get_idx(corner, self % sizeN)
!    if (idx == 0) call fatalError(Here, 'Point is outside grid: '//numToChar(r))

    val = self % gridCells(idx) % majorant

    if (val < ZERO) call fatalError(Here, 'Invalid majorant: '//numToChar(val))

  end function getValue

  !!
  !!
  !!
  subroutine storeMats(self, searchN)
    class(simpleGrid), intent(inout)              :: self
    integer(shortInt), dimension(3), intent(in)   :: searchN
    real(defReal), dimension(3)                   :: searchRes
    integer(shortInt)                             :: i, j, k, l, matIdx, id
    real(defReal), dimension(3)                   :: corner, r
    type(dynIntArray)                             :: mats

    ! Calculate distance between search points
    searchRes = self % pitch / (searchN + 1)

    ! Loop through grid cells
    do i = 1, size(self % gridCells)

      ! Get cell lower corner
      corner = self % corner + self % pitch * (get_ijk(i, self % sizeN) - 1)

      ! Loop through search locations
      do j = 1, searchN(1)
        do k = 1, searchN(2)
          do l = 1, searchN(3)
            ! Find matIdx at search location
            r = corner + [j, k, l] * searchRes
            call self % mainGeom % whatIsAt(matIdx, id, r)

            ! Add to array if not already present
            if (mats % isPresent(matIdx)) then
              ! Do nothing
            else
              call mats % add(matIdx) 
            end if

          end do
        end do
      end do

      ! Store matIdx data in grid cell
      self % gridCells(i) % mats = mats % expose()
      call mats % kill()

    end do

  end subroutine storeMats

  !!
  !!
  !!
  subroutine update(self)
    class(simpleGrid), intent(inout) :: self
    integer(shortInt)                :: i
    integer(shortInt), save          :: j, matIdx
    real(defReal), save              :: sigmaT
    class(particle), allocatable     :: p
    !$omp threadprivate(j, matIdx)

    allocate(p)
    p % G = 1

    !$omp parallel do
    ! Loop through grid cells
    do i = 1, size(self % gridCells)
      ! Reset majorant
      self % gridCells(i) % majorant = ZERO

      do j = 1, size(self % gridCells(i) % mats)
        ! Get opacity of each material
        matIdx = self % gridCells(i) % mats(j)
        if (matIdx /= 0) then
          sigmaT = self % xsData % getTransMatXS(p, matIdx)
          ! Update majorant if required
          if (sigmaT > self % gridCells(i) % majorant) self % gridCells(i) % majorant = sigmaT
        end if

      end do
    end do
    !$omp end parallel do

  end subroutine update



  !!
  !! Generate ijk from localID and shape
  !!
  !! Args:
  !!   localID [in] -> Local id of the cell between 1 and product(sizeN)
  !!   sizeN [in]   -> Number of cells in each cardinal direction x, y & z
  !!
  !! Result:
  !!   Array ijk which has integer position in each cardinal direction
  !!
  pure function get_ijk(localID, sizeN) result(ijk)
    integer(shortInt), intent(in)               :: localID
    integer(shortInt), dimension(3), intent(in) :: sizeN
    integer(shortInt), dimension(3)             :: ijk
    integer(shortInt)                           :: temp, base

    temp = localID - 1

    base = temp / sizeN(1)
    ijk(1) = temp - sizeN(1) * base + 1

    temp = base
    base = temp / sizeN(2)
    ijk(2) = temp - sizeN(2) * base + 1

    ijk(3) = base + 1

  end function get_ijk


  pure function get_idx(ijk, sizeN) result(idx)
    integer(shortInt), dimension(3), intent(in) :: ijk
    integer(shortInt), dimension(3), intent(in) :: sizeN
    integer(shortInt)                           :: idx

    if (any(ijk <= 0 .or. ijk > sizeN)) then ! Point is outside grid
      idx = 0
    else
      idx = ijk(1) + sizeN(1) * (ijk(2)-1 + sizeN(2) * (ijk(3)-1))
    end if

  end function get_idx

  !!
  !! Adjustment for surface tolerance used by getValue subroutine
  !!
  function reposition(r, bounds) result(rNew)
    real(defReal), dimension(3), intent(in) :: r
    real(defReal), dimension(6), intent(in) :: bounds
    real(defReal), dimension(3)             :: rNew
    integer(shortInt)                       :: i

    rNew = r

    do i = 1, 3
      if (r(i) < bounds(i)   .and. r(i) > bounds(i)  -SURF_TOL) rNew(i) = bounds(i)
      if (r(i) > bounds(i+3) .and. r(i) < bounds(i+3)+SURF_TOL) rNew(i) = bounds(i+3)
    end do

    ! TODO Boundaries between cells rather than just edge of grid

  end function reposition

  !!
  !! Adjustment for surface tolerance used by getDistance function.
  !! Able to be simpler than repositionLoc as only consider position within cell
  !! rather than within grid.
  !!
  !! Args:
  !!   r  [inout] -> position as a fraction of distance across cell, 0 < r(i), < 1
  !!   u  [in]    -> direction
  !!   pitch [in] -> grid resolution
  !!
!  subroutine repositionDist(r_bar, u, pitch)
!    real(defReal), dimension(3), intent(inout) :: r_bar
!    real(defReal), dimension(3), intent(in)    :: u
!    real(defReal), dimension(3), intent(in)    :: pitch
!    real(defReal), dimension(3)                :: low, high
!    integer(shortInt)                          :: i
!
!    ! Calculate cut-offs
!    low = SURF_TOL / pitch
!    high = ONE - low
!
!    ! Change position if needed
!    do i = 1, 3
!      if (r_bar(i) < low(i)  .and. u(i) < ZERO) r_bar(i) = ONE
!      if (r_bar(i) > high(i) .and. u(i) > ZERO) r_bar(i) = ZERO
!    end do
!
!  end subroutine repositionDist

end module simpleGrid_class
