module xPlane_class

  use numPrecision
  use universalVariables
  use genericProcedures,    only : fatalError, dotProduct
  use dictionary_class,     only : dictionary
  use surface_inter,        only : surface

  implicit none
  private

  !!
  !! Constructor
  !!
  interface xPlane
    module procedure xPlane_fromDict
  end interface

  !!
  !! Simple plane perpendicular to x-axis
  !!
  type, public, extends(surface) :: xPlane
    real(defReal) :: x0 ! x-axis offset

  contains
    procedure :: init
    procedure :: evaluate
    procedure :: distanceToSurface
    procedure :: normalVector
    procedure :: whichSurface
    procedure :: setBoundaryConditions
    procedure :: boundaryTransform

    procedure,private :: reflectiveTransform

  end type xPlane

contains

  !!
  !! Initialise X-Plane from offset
  !!
  subroutine init(self, x0, id, name)
    class(xPlane), intent(inout)            :: self
    real(defReal), intent(in)               :: x0
    integer(shortInt), intent(in), optional :: id
    character(*), optional, intent(in)      :: name

    self % x0 = x0
    if(present(id)) self % id = id
    if(present(name)) self % name = name

  end subroutine init

  !!
  !! Returns an initialised instance of xPlane for dictionary and name
  !!
  function xPlane_fromDict(dict,name) result(new)
    class(dictionary), intent(in)  :: dict
    character(nameLen), intent(in) :: name
    type(xPlane)                   :: new
    integer(shortInt)              :: id
    real(defReal)                  :: x0
    character(100),parameter :: Here =' xPlane_fromDict ( xPlane_class.f90)'

    id = dict % getInt('id')
    if(id < 1) call fatalError(Here,'Invalid surface id provided')

    x0 = dict % getReal('x')
    call new % init(x0, id, name)

  end function xPlane_fromDict

  !!
  !!  Evaluate plane distance
  !!
  function evaluate(self, r) result(res)
    class(xPlane), intent(in)               :: self
    real(defReal), dimension(3), intent(in) :: r
    real(defReal)                           :: res

    res = r(1) - self % x0

  end function evaluate

  !!
  !! Calculate distance to plane along direction u
  !!
  function distanceToSurface(self,r,u)result(distance)
    class(xPlane), intent(in)               :: self
    real(defReal), dimension(3), intent(in) :: r, u
    real(defReal)                           :: distance, u1

    u1 = u(1)
    distance = self%x0 - r(1)
    if ((u1==ZERO) .OR. (abs(distance) < surface_tol)) then
      distance = INFINITY
      return
    end if

    distance = distance/u1
    if (distance < ZERO) distance = INFINITY
    return

  end function distanceToSurface

  !!
  !! Perform reflection
  !!
  subroutine reflectiveTransform(self, r, u)
    class(xPlane), intent(in)                  :: self
    real(defReal), dimension(3), intent(inout) :: r, u
    real(defReal)                              :: xDisplacement

    ! Reflect the particle x-coordinate across the plane
    xDisplacement = r(1) - self%x0
    r(1) = r(1) - TWO*xDisplacement

    ! Reflect the particle direction (independent of intersection point for plane)
    u(1) = -u(1)

  end subroutine reflectiveTransform

  !!
  !! Return normal of the plane
  !!
  function normalVector(self,r)result(normal)
    class(xPlane), intent(in)               :: self
    real(defReal), dimension(3)             :: normal
    real(defReal), dimension(3), intent(in) :: r

    normal = [ONE, ZERO, ZERO]

  end function normalVector

  !!
  !! Give an error: this routine should not be called for a non-compound surface
  !!
  function whichSurface(self, r, u) result(surfPointer)
    class(xPlane), intent(in)               :: self
    real(defReal), dimension(3), intent(in) :: r, u
    class(surface), pointer                 :: surfPointer
    character(100),parameter :: Here ='whichSurface ( xPlane_class.f90)'

    call fatalError(Here,'This function should never be called for a simple surface')

  end function whichSurface

  !!
  !! Crash on attempting to set boundary conditions for a plane object
  !!
  subroutine setBoundaryConditions(self, BC)
    class(xPlane), intent(inout)                :: self
    integer(shortInt), dimension(:), intent(in) :: BC
    character(100),parameter :: Here = 'setBoundaryConditions ( xPlane_class.f90)'

    call fatalError(Here,'Boundary conditions may not be set for a plane surface')

  end subroutine setBoundaryConditions

  !!
  !! Apply boundary transformations
  !!
  subroutine boundaryTransform(self, r, u, isVacuum)
    class(xPlane), intent(in)                  :: self
    real(defReal), dimension(3), intent(inout) :: r
    real(defReal), dimension(3), intent(inout) :: u
    logical(defBool), intent(inout)            :: isVacuum
    character(100),parameter :: Here =' boundaryTransform ( xPlane_class.f90)'

    if (self % isVacuum) then
      isVacuum = .TRUE.
    else if (self % isPeriodic) then
      r = r + self % periodicTranslation
    else if (self % isReflective) then
      call self % reflectiveTransform(r,u)
    else
      call fatalError(Here,'No boundary condition applied to surface')
    end if

  end subroutine boundaryTransform
    
end module xPlane_class
