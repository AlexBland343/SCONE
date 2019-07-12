module aceNeutronNuclide_iTest

  use numPrecision
  use aceCard_class,           only : aceCard
  use ceNeutronDatabase_inter, only : ceNeutronDatabase
  use aceNeutronNuclide_class, only : aceNeutronNuclide

  implicit none


contains

  !!
  !! Load and verify functions of aceNeutronNuclide initialised to O-16
  !!
@Test
  subroutine testACEnuclideO16()
    type(aceNeutronNuclide), target   :: nuc
    type(aceCard)                     :: ACE
    class(ceNeutronDatabase), pointer :: database => null()

    ! Build ACE library
    call ACE % readFromFile('./IntegrationTestFiles/8016JEF311.ace', 1)

    ! Build nuclide
    call nuc % init(ACE, 1, database)


  end subroutine testACEnuclideO16

    
end module aceNeutronNuclide_iTest
