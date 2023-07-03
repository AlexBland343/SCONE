module IMCMaterial_inter

  use numPrecision
  use particle_class,       only : particle
  use RNG_class,            only : RNG

  ! Nuclear Data Interfaces
  use materialHandle_inter,    only : materialHandle
  use IMCXsPackages_class,     only : IMCMacroXSs

  implicit none
  private

  !!
  !! Public Pointer Cast
  !!
  public :: IMCMaterial_CptrCast

  !!
  !! Abstract interface far all IMC Materials (CE and MG)
  !!
  !! It was created to expose access to some key information in the context of
  !! tallying where one is not interested whether MG or CE data is used
  !!
  !! Interface:
  !!   materialHandle interface 
  !!   getMacroXSs -> Return Macroscopic XSs given particle with energy data
  !!
  type, public, abstract, extends(materialHandle) :: IMCMaterial
    private
  contains
    generic                              :: getMacroXSs => getMacroXSs_byP
    procedure(getMacroXSs_byP), deferred :: getMacroXSs_byP
    procedure(updateMat), deferred       :: updateMat
    procedure(getEmittedRad), deferred   :: getEmittedRad
    procedure(getFleck), deferred        :: getFleck
    procedure(getEta), deferred          :: getEta
    procedure(getTemp), deferred         :: getTemp
    procedure(getMatEnergy), deferred    :: getMatEnergy
    procedure(setCalcType), deferred     :: setCalcType
    procedure(sampleTransformTime), deferred :: sampleTransformTime
  end type IMCMaterial

  abstract interface

    !!
    !! Return Macroscopic XSs for the material given particle
    !!
    !! Args:
    !!   xss [out]    -> Cross section package to store the data
    !!   p [in]       -> Particle that provides energy or energy group
    !!
    !! Errors:
    !!   fatalError if energy value/group is outside bounds
    !!   fatalError if MG particle is given to CE data and vice versa
    !!
    subroutine getMacroXSs_byP(self, xss, p)
      import :: IMCMaterial, particle, IMCMacroXSs
      class(IMCMaterial), intent(in)     :: self
      type(IMCMacroXSs), intent(out)     :: xss
      class(particle), intent(in)        :: p
    end subroutine getMacroXSs_byP

    !!
    !! Update material properties at each time step
    !! First update energy using simple balance, then solve for temperature,
    !!  then update temperature-dependent properties
    !!
    !! Args:
    !!   tallyEnergy [in] -> Energy absorbed into material
    !!   printUpdate [in, optional] -> Bool, if true then will print updates to screen
    !!
    subroutine updateMat(self, tallyEnergy, printUpdate)
      import :: IMCMaterial, defReal, defBool
      class(IMCMaterial), intent(inout)      :: self
      real(defReal), intent(in)              :: tallyEnergy
      logical(defBool), intent(in), optional :: printUpdate
    end subroutine updateMat

    !!
    !! Return the equilibrium radiation energy density, U_r
    !!
    function getEmittedRad(self) result(emittedRad)
      import :: IMCMaterial, defReal, RNG
      class(IMCMaterial), intent(inout)  :: self
      real(defReal)                      :: emittedRad
    end function getEmittedRad

    !!
    !! Get Fleck factor of material
    !!
    function getFleck(self) result(fleck)
      import :: IMCMaterial, defReal
      class(IMCMaterial), intent(in) :: self
      real(defReal)                  :: fleck
    end function getFleck

    !!
    !! Return eta = aT**4/U_m
    !!
    !! Currently only used in transportOperatorIMC_class.f90 for ISMC calculations
    !!
    function getEta(self) result(eta)
      import :: IMCMaterial, defReal
      class(IMCMaterial),intent(in) :: self
      real(defReal)                 :: eta
    end function getEta

    !!
    !! Get temperature of material
    !!
    function getTemp(self) result(T)
      import :: IMCMaterial, defReal
      class(IMCMaterial), intent(inout) :: self
      real(defReal)                     :: T
    end function getTemp

    !!
    !! Return material energy
    !!
    function getMatEnergy(self) result(energy)
      import :: IMCMaterial, defReal
      class(IMCMaterial), intent(inout) :: self
      real(defReal)                     :: energy
    end function getMatEnergy

    !!
    !! Set the calculation type to be used
    !!
    !! Current options:
    !!   IMC
    !!   ISMC
    !!
    !! Errors:
    !!   Unrecognised option
    !!
    subroutine setCalcType(self, calcType)
      import :: IMCMaterial, shortInt
      class(IMCMaterial), intent(inout) :: self
      integer(shortInt), intent(in)     :: calcType
    end subroutine setCalcType

    !!
    !! Sample the time taken for a material particle to transform into a photon
    !! Used for ISMC only
    !!
    function sampleTransformTime(self, rand) result(t)
      import :: IMCMaterial, RNG, defReal
      class(IMCMaterial), intent(inout) :: self
      class(RNG), intent(inout)         :: rand
      real(defReal)                     :: t
    end function sampleTransformTime

  end interface

contains


  !!
  !! Cast materialHandle pointer to IMCMaterial pointer
  !!
  !! Args:
  !!   source [in]    -> source pointer of class materialHandle
  !!
  !! Result:
  !!   Null if source is not of IMCMaterial
  !!   Pointer to source if source is IMCMaterial class
  !!
  pure function IMCMaterial_CptrCast(source) result(ptr)
    class(materialHandle), pointer, intent(in) :: source
    class(IMCMaterial), pointer                :: ptr

    select type(source)
      class is(IMCMaterial)
        ptr => source

      class default
        ptr => null()
    end select

  end function IMCMaterial_CptrCast

end module IMCMaterial_inter
