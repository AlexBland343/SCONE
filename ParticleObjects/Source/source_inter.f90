module source_inter

  use numPrecision
  use particle_class,        only : particle, particleState
  use particleDungeon_class, only : particleDungeon
  use dictionary_class,      only : dictionary
  use RNG_class,             only : RNG
  use geometry_inter,        only : geometry
  use genericProcedures,    only : fatalError

  implicit none
  private

  !!
  !! Extendable scource class procedures
  !!
  public :: kill

  !!
  !! Abstract interface of source for particles
  !!
  !! Source generates particles from specified distributions
  !! for, e.g., fixed source calcs. or to generate initial
  !! distribution for eigenvalue calcs
  !!
  !! Public members:
  !!   geom -> Pointer to the geometry to ensure source is inside and
  !!           for more complicated source distribution
  !!
  !! Interface:
  !!   init              -> initialise the source
  !!   generate          -> generate particles to fill a dungeon
  !!   sampleParticle    -> sample particles from the corresponding distributions
  !!   kill              -> clean up the source
  !!
  type, public,abstract :: source
    private
    class(geometry), pointer, public       :: geom => null()
    integer(shortInt), dimension(:), allocatable, public :: matPops
  contains
    procedure, non_overridable             :: generate
    procedure, non_overridable             :: append
    procedure, non_overridable             :: appendIMC
    procedure(sampleParticle), deferred    :: sampleParticle
    procedure(init), deferred              :: init
    procedure(kill), deferred              :: kill
  end type source

  abstract interface

    !!
    !! Initialise source from dictionary & geometry
    !!
    !! Args:
    !!   dict [in] -> dict containing point source information
    !!   geom [in] -> pointer to a geometry
    !!
    subroutine init(self, dict, geom)
      import :: source, &
                dictionary, &
                geometry
      class(source), intent(inout)         :: self
      class(dictionary), intent(in)        :: dict
      class(geometry), pointer, intent(in) :: geom
    end subroutine init

    !!
    !! Sample particle's phase space co-ordinates
    !!
    !! Generates a phase-space state for a single particle
    !!
    !! Args:
    !!   p [inout] -> particle to be over-written
    !!
    !! Result:
    !!   A particle sampled the prescribed source
    !!
    function sampleParticle(self, rand) result(p)
      import :: source, particleState, RNG
      class(source), intent(inout)       :: self
      class(RNG), intent(inout)          :: rand
      type(particleState)                :: p
    end function sampleParticle

  end interface

contains

    !!
    !! Generate particles to populate a particleDungeon
    !!
    !! Fills a particle dungeon with n particles, sampled
    !! from the corresponding source distributions
    !!
    !! Args:
    !!   dungeon [inout] -> particle dungeon to be populated
    !!   n [in]          -> number of particles to place in dungeon
    !!
    !! Result:
    !!   A dungeon populated with n particles sampled from the source
    !!
    subroutine generate(self, dungeon, n, rand)
      class(source), intent(inout)         :: self
      type(particleDungeon), intent(inout) :: dungeon
      integer(shortInt), intent(in)        :: n
      class(RNG), intent(inout)            :: rand
      integer(shortInt)                    :: i

      ! Set dungeon size to begin
      call dungeon % setSize(n)

      ! Generate n particles to populate dungeon
      do i = 1, n
        call dungeon % replace(self % sampleParticle(rand), i)
      end do

    end subroutine generate

    !!
    !! Generate particles to populate a particleDungeon without overriding
    !! particles already present
    !!
    !! Adds to a particle dungeon n particles, sampled
    !! from the corresponding source distributions
    !!
    !! Args:
    !!   dungeon [inout] -> particle dungeon to be populated
    !!   n [in]          -> number of particles to place in dungeon
    !!
    !! Result:
    !!   A dungeon populated with n particles sampled from the source
    !!
    subroutine append(self, dungeon, n, rand)
      class(source), intent(inout)         :: self
      type(particleDungeon), intent(inout) :: dungeon
      integer(shortInt), intent(in)        :: n
      class(RNG), intent(inout)            :: rand
      integer(shortInt)                    :: i

      ! Generate n particles to populate dungeon
      do i = 1, n
        call dungeon % detain(self % sampleParticle(rand))
      end do

    end subroutine append

    !!
    !! Generate n particles to populate a particleDungeon without overriding
    !! particles already present. Unlike 'append' subroutine above, this is
    !! specific to IMCSource_class and is needed for multiregion functionality.
    !! The number of particles sampled in each matIdx is tallied and used to normalise
    !! each particle weight, so that the total energy emitted in each region is as
    !! required
    !!
    !! Args:
    !!   dungeon [inout] -> particle dungeon to be populated
    !!   n [in]          -> number of particles to place in dungeon
    !!
    !! Result:
    !!   A dungeon populated with n particles sampled from the source
    !!
    subroutine appendIMC(self, dungeon, n, rand)
      class(source), intent(inout)         :: self
      type(particleDungeon), intent(inout) :: dungeon
      type(particleDungeon)                :: tempDungeon
      type(particle)                       :: p
      integer(shortInt), intent(in)        :: n
      class(RNG), intent(inout)            :: rand
      integer(shortInt)                    :: i
      real(defReal)                        :: normFactor
      character(100), parameter            :: Here = "appendIMC (source_inter.f90)"

      ! Reset particle population counters
      do i = 1, size( self % matPops )
        self % matPops(i) = 0
      end do

      ! Set temporary dungeon size
      call tempDungeon % setSize(n)

      ! Generate n particles to populate temporary dungeon
      do i = 1, n
        call tempDungeon % replace(self % sampleParticle(rand), i)
      end do

      ! Call error if any region contains no generated particles
      if ( minval(self % matPops) == 0 ) then
        ! Currently will lead to energy imbalance as mat energy will be reduced by emittedRad but
        !  no particles will be carrying it, possible to modify code to maintain energy balance
        call fatalError(Here, "Not all regions emitted particles, use more particles")
      end if

      ! Loop through again and add to input dungeon, normalising energies based on material
      do i = 1, n

        call tempDungeon % release(p)

        ! Place inside geometry to set matIdx, for some reason resets when released from dungeon
        call self % geom % placeCoord( p % coords )

        ! Normalise
        normFactor = self % matPops( p % coords % matIdx )
        p % w = p % w / normFactor

        ! Add to input dungeon
        call dungeon % detain(p)

      end do        

    end subroutine appendIMC

    !!
    !! Return to uninitialised state
    !!
    elemental subroutine kill(self)
      class(source), intent(inout) :: self

      self % geom => null()

    end subroutine kill

end module source_inter
