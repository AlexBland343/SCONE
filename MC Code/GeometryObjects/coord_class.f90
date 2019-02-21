module coord_class
  use numPrecision
  use universalVariables
  use genericProcedures, only : rotateVector, fatalError, numToChar

  implicit none
  private

  !!
  !! Data relating to the location of a particle at a given level in a geometry
  !! Coordinates are realible when:
  !!   -> norm2(dir) = 1
  !!   -> uniIdx & cellIdx > 0
  !!
  !! *** NOTE will store coordinate rotations to reapply them
  !!
  type, public :: coord
    real(defReal), dimension(3) :: r         = ZERO    ! position
    real(defReal), dimension(3) :: dir       = ZERO    ! direction
    logical(defBool)            :: isRotated = .FALSE. ! is the co-ordinate in a rotated reference frame?
    integer(shortInt)           :: uniIdx    = 0       ! Index of the universe definition occupied
    integer(shortInt)           :: uniRootID = 0       ! Unique ID = uniRootID + localID
    integer(shortInt)           :: localID   = 0       ! ID of the cell occupied within local universe
    integer(shortInt)           :: cellIdx   = 0       ! Index of a cell definition occupied
  contains
    procedure :: isValid => isValid_coord
    procedure :: display => display_coord
  end type coord

  !!
  !! PART OF GEOMETRY INTERFACE
  !! List of coordinets at diffrent level of a geometry
  !!
  !! Following states are possible:
  !!  uninitialised    -> Nesting is < 1. All coordinate values are unreliable
  !!  above geometry   -> Nesting = 1. matIdx is equal to 0 (unassigned)
  !!                                   coordinates at nesting level 1 are realible
  !!  inside geometry  -> Nesting >=1. matIdx is assigned.
  !!                                   coordinates up to nesting are realible
  !! IMPORTANT NOTE:
  !!   moveGlobal resets regionID & matIdx to 0
  !!   moveLocal  leaves regionID & matIdx unchanged
  !!
  !! * RegionID should be part of coord becouse multiple cells are occupied at diffrent levels
  !!
  type, public :: coordList
    integer(shortInt)                          :: nesting = 0      ! depth of co-ordinate nesting
    type(coord), dimension(hardcoded_max_nest) :: lvl              ! array of coords nested successively deeper
    integer(shortInt)                          :: matIdx = 0       ! index of the material occupied
  contains
    ! Build procedures
    procedure :: init

    ! State enquiry procedures
    procedure :: isPlaced
    procedure :: isAbove
    procedure :: isUninitialised

    ! Interface procedures
    procedure :: addLevel
    procedure :: decreaseNesting
    procedure :: takeAboveGeom
    procedure :: moveGlobal
    procedure :: moveLocal
    procedure :: rotate
    procedure :: cell
    procedure :: assignPosition
    procedure :: assignDirection
    procedure :: uniqueId

  end type coordList

contains

  !!
  !! Returns .true. if coordinates are valid
  !!
  function isValid_coord(self) result(correct)
    class(coord), intent(in) :: self
    logical(defBool)         :: correct

    ! Direction vector is normalised within floating point tolerance
    correct = abs(norm2(self % dir) - ONE) < floatTol

    correct = correct .and. self % uniIdx  > 0
    correct = correct .and. self % cellIdx > 0

  end function isValid_coord

  !!
  !! Print to screen contents of the coord
  !!
  subroutine display_coord(self)
    class(coord), intent(in) :: self

    print *, "R: ", self % r, " U: ", self % dir
    print *, "UniIDx: ", numToChar(self % uniIDx), " LocalID: ", numToChar(self % localID)

  end subroutine display_coord


  !!
  !! Initialise coordList.
  !! Upon execution coordList is above geometry
  !!
  pure subroutine init(self, r, dir)
    class(coordList), intent(inout)         :: self
    real(defReal), dimension(3), intent(in) :: r
    real(defReal), dimension(3), intent(in) :: dir

    call self % takeAboveGeom()

    self % lvl(1) % r = r
    self % lvl(1) % dir = dir
    self % nesting = 1

  end subroutine init

  !!
  !! Return true if coordinates List is placed in geometry
  !!
  elemental function isPlaced(self) result(isIt)
    class(coordList), intent(in) :: self
    logical(defBool)             :: isIt

    isIt = (self % matIdx > 0) .and. (self % nesting >= 1)

  end function isPlaced

  !!
  !! Return ture if coordinates are above geometry
  !!
  elemental function isAbove(self) result(isIt)
    class(coordList), intent(in) :: self
    logical(defBool)             :: isIt

    isIt = (self % matIdx <= 0) .and. (self % nesting == 1)

  end function isAbove

  !!
  !! Return true if coordinates are uninitialised
  !!
  elemental function isUninitialised(self)  result(isIt)
    class(coordList), intent(in) :: self
    logical(defBool)             :: isIt

    isIt = .not.( self % isPlaced() .or. self % isAbove() )

  end function isUninitialised


  !!
  !! Add another level of co-ordinates
  !! Apply provided offset
  !! Translational transformation is only supported
  !!
  pure subroutine addLevel(self, offset, uniIdx, uniRootID)
    class(coordList), intent(inout)         :: self
    real(defReal), dimension(3), intent(in) :: offset
    integer(shortInt), intent(in)           :: uniIdx
    integer(shortInt), intent(in)           :: uniRootID
    integer(shortInt)                       :: n
    character(100),parameter :: Here ='addLevel (coord_class.f90)'

    n = self % nesting + 1
    self % nesting = n

    self % lvl(n) % r         = self % lvl(n-1) % r - offset
    self % lvl(n) % dir       = self % lvl(n-1) % dir
    self % lvl(n) % uniIdx    = uniIdx
    self % lvl(n) % uniRootID = uniRootID

  end subroutine addLevel

  !!
  !! Changes state of the coordList to above the geometry
  !! Does not change position or direction at nesting level 1
  !!
  elemental subroutine takeAboveGeom(self)
    class(coordList), intent(inout) :: self

    self % nesting  = 1
    self % matIdx   = 0

  end subroutine takeAboveGeom

  !!
  !! Move the co-ordinates to the chosen level
  !! Returns error if n > self % nesting
  !!
  subroutine decreaseNesting(self,n)
    class(coordList), intent(inout)         :: self
    integer(shortInt), intent(in), optional :: n
    character(100),parameter :: Here='decreaseNesting ( coord_class.f90)'

    if (n > self % nesting) call fatalError(Here,' New nesting level > old nesting level')

    self % nesting = n

  end subroutine decreaseNesting

  !!
  !! Move a point in above the geometry
  !! Takes the coordList above the geometry
  !!
  elemental subroutine moveGlobal(self, distance)
    class(coordList), intent(inout) :: self
    real(defReal), intent(in)       :: distance

    call self % takeAboveGeom()
    self % lvl(1) % r = self % lvl(1) % r + distance * self % lvl(1) % dir

  end subroutine moveGlobal

  !!
  !! Move a point in local co-ordinates down to nesting level n
  !! Changes nesting to n
  !! NOTE: Does not change regionID and matIdx!!!
  !!
  subroutine moveLocal(self, distance, n)
    class(coordList), intent(inout) :: self
    real(defReal), intent(in)       :: distance
    integer(shortInt), intent(in)   :: n
    integer(shortInt)               :: i

    call self % decreaseNesting(n)
    do i=1,n
      self % lvl(i) % r = self % lvl(i) % r + distance * self % lvl(i) % dir
    end do

  end subroutine moveLocal

  !!
  !! Rotate neutron direction
  !! Applies rotation vector to lower levels only if they are in a rotated geometry
  !! Otherwise, copies direction from the level above
  !!
  elemental subroutine rotate(self,mu,phi)
    class(coordList), intent(inout) :: self
    real(defReal), intent(in)       :: mu
    real(defReal), intent(in)       :: phi
    integer(shortInt)               :: i

    ! Rotate directions in all nesting levels
    self % lvl(1) % dir = rotateVector(self % lvl(1) % dir, mu, phi)

    ! Propagate rotation to lower levels
    do i = 2,self % nesting
      if (self % lvl(i) % isRotated) then
        self % lvl(i) % dir = rotateVector(self % lvl(i) % dir, mu, phi)

      else
        self % lvl(i) % dir = self % lvl(i-1) % dir

      end if
    end do

  end subroutine rotate

  !!
  !! Returns the index of the cell occupied at the lowest level
  !!
  elemental function cell(self)result(cellIdx)
    class(coordList), intent(in) :: self
    integer(shortInt)            :: cellIdx

    cellIdx = self % lvl(self % nesting) % cellIdx

  end function cell

  !!
  !! Assign the global position to an arbitrary value
  !! Takes the coordinates above the geometry
  !! NOTE: Resets region index and material index !!!
  !!
  pure subroutine assignPosition(self, r)
    class(coordList), intent(inout)         :: self
    real(defReal), dimension(3), intent(in) :: r

    call self % takeAboveGeom()
    self % lvl(1) % r = r

  end subroutine assignPosition

  !!
  !! Assign the global direction to an arbitrary value
  !! NOTE: Does not support rotated co-ordinate frames
  !!       Does NOT reset regionId & matIdx
  !!
  subroutine assignDirection(self, dir)
    class(coordList), intent(inout)         :: self
    real(defReal), dimension(3), intent(in) :: dir
    integer(shortInt)                       :: i
    character(100),parameter :: Here = 'assignDirection (coord_class.f90)'

    ! Assign new direction in global frame
    self % lvl(1) % dir = dir

    ! Propage the change to lower levels
    do i=2,self % nesting
      if(self % lvl(i) % isRotated) then
        call fatalError(Here,'Rotated levels are not yet implemented')

      else
        self % lvl(i) % dir = dir

      end if
    end do

  end subroutine assignDirection

  !!
  !! Returns unique ID of the lowest level cell in geometry
  !!
  elemental function uniqueId(self) result(id)
    class(coordList), intent(in) :: self
    integer(shortInt)            :: id
    integer(shortInt) :: n

    n = self % nesting

    id = self % lvl(n) % uniRootID + self % lvl(n) % localID

  end function uniqueId

end module coord_class
