module particleDungeon_class

  use numPrecision
  use genericProcedures,     only : fatalError, numToChar
  use particle_class,        only : particle, particleState, P_MATERIAL, P_PHOTON
  use RNG_class,             only : RNG
  use geometry_inter,        only : geometry
  use universalVariables,    only : INF

  implicit none
  private

  !!
  !! particleDungeon stores particle phase-space
  !! Used in eigenvalue calculation to store fission sites generated in a cycle
  !! Similar structures are refered to as:
  !! Store: MONK and Serpent(?)
  !! Fission Bank: OpenMC and MCNP(?)
  !!
  !! NOTE INCONSISTANT DEFINITIONS
  !! ****
  !! For convinience it allows to store value of k-eff that can be retrieved to adjust fission site
  !! generation rate during a calculation. It is not currently used during normalisation but
  !! is used by analog k-eff tally. It is necessary to clarify behaviour.
  !! ****
  !!
  !! Technically not the whole particles are stored but only the key data defined in phaseCoord
  !!
  !! Dungeon can work like stacks or arrays. Stack-like behaviour is not really thread safe
  !! so it can be utilised when collecting and processing secondary particles in history
  !! that should be processed during the course of one cycle. Array-like behaviour allows to
  !! easily distribute particles among threads. As long as indices assign to different threads
  !! do not overlap, reading is thread-safe (I hope-MAK).
  !!
  !!
  !! INTERFACE:
  !!   Stack-like interface:
  !!     detain(particle)   -> adda a particle to the top
  !!     release(particle)  -> removes a particle from the top. Sets p % isDead = .false.
  !!
  !!   Array-like interface:
  !!     replace(particle, i) -> overwrite prisoner data at index i
  !!     copy(particle, i)    -> copy prisoner at index i into particle. Sets p % isDead = .false.
  !!     get(i)               -> function returns particle state at index i
  !!
  !!   Misc procedures:
  !!     isEmpty()         -> returns .true. if there are no more particles
  !!     cleanPop()        -> kill or prisoners
  !!     normWeight(totWgt)-> normalise dungeon population so its total weight is totWgt
  !!     normSize(N)       -> normalise dungeon population so it contains N particles
  !!                          does not take ununiform weight of particles into account
  !!     setSize(n)        -> sizes dungeon to have n dummy particles for ease of overwriting
  !!     printToFile(name) -> prints population in ASCII format to file "name"
  !!     printToScreen(prop,nMax,total) -> prints property to screen for up to nMax particles
  !!     popSize()         -> returns number of particles in dungeon
  !!     popWeight()       -> returns total population weight
  !!
  !!   Build procedures:
  !!     init(maxSize)     -> allocate space to store maximum of maxSize particles
  !!     kill()            -> return to uninitialised state
  !!
  type, public :: particleDungeon
    private
    real(defReal),public     :: k_eff = ONE   ! k-eff for fission site generation rate normalisation
    integer(shortInt)        :: pop = 0       ! Current population size of the dungeon

    ! Storage space
    type(particleState), dimension(:), allocatable :: prisoners

  contains
    !! Build procedures
    procedure  :: init
    procedure  :: kill

    !! Stack-like interface
    generic    :: detain  => detain_particle, detain_particleState
    procedure  :: release

    !! Array-like interface
    generic    :: replace => replace_particle, replace_particleState
    procedure  :: copy
    procedure  :: get

    !! Misc Procedures
    procedure  :: isEmpty
    procedure  :: normWeight
    procedure  :: normSize
    procedure  :: reduceSize
    procedure  :: reduceSize2
    procedure  :: reduceSize3
    procedure  :: combine
    procedure  :: cleanPop
    procedure  :: popSize
    procedure  :: popWeight
    procedure  :: setSize
    procedure  :: printToFile
    procedure  :: printToScreen

    ! Private procedures
    procedure, private :: detain_particle
    procedure, private :: detain_particleState
    procedure, private :: replace_particle
    procedure, private :: replace_particleState
  end type particleDungeon

contains

  !!
  !! Allocate space for the particles
  !!
  subroutine init(self,maxSize)
    class(particleDungeon), intent(inout) :: self
    integer(shortInt), intent(in)         :: maxSize

    if(allocated(self % prisoners)) deallocate(self % prisoners)
    allocate(self % prisoners(maxSize))
    self % pop    = 0

  end subroutine init

  !!
  !! Deallocate memory and return to uninitialised state
  !!
  elemental subroutine kill(self)
    class(particleDungeon), intent(inout) :: self

    ! Reset settings
    self % pop = 0

    ! Deallocate memeory
    if(allocated(self % prisoners)) deallocate(self % prisoners)

  end subroutine kill

  !!
  !! Store particle in the dungeon
  !!
  subroutine detain_particle(self,p)
    class(particleDungeon), intent(inout) :: self
    class(particle), intent(in)           :: p
    character(100),parameter              :: Here = 'detain_particle (particleDungeon_class.f90)'

    ! Increase population and weight
    self % pop = self % pop +1

    ! Check for population overflow
    if (self % pop > size(self % prisoners)) then
      call fatalError(Here,'Run out of space for particles.&
                           & Max size:'//numToChar(size(self % prisoners)) //&
                            ' Current population: ' // numToChar(self % pop))
    end if

    ! Load new particle
    self % prisoners(self % pop) = p

  end subroutine detain_particle

  !!
  !! Store phaseCoord in the dungeon
  !!
  subroutine detain_particleState(self,p_state)
    class(particleDungeon), intent(inout) :: self
    type(particleState), intent(in)       :: p_state
    character(100), parameter    :: Here = 'detain_particleState (particleDungeon_class.f90)'

    ! Increase population
    self % pop = self % pop +1

    ! Check for population overflow
    if (self % pop > size(self % prisoners)) then
      call fatalError(Here,'Run out of space for particles.&
                           & Max size:'//numToChar(size(self % prisoners)) //&
                            ' Current population: ' // numToChar(self % pop))
    end if

    ! Load new particle
    self % prisoners(self % pop) = p_state

  end subroutine detain_particleState

  !!
  !! Pop the particle from the top of the dungeon.
  !! Makes particle alive at exit
  !!
  subroutine release(self, p)
    class(particleDungeon), intent(inout) :: self
    type(particle), intent(inout)         :: p
    integer(shortInt)                     :: pop

    ! Load data into the particle
    pop = self % pop
    p = self % prisoners(pop)
    p % isDead = .false.

    ! Decrease population
    self % pop = self % pop - 1

  end subroutine release

  !!
  !! Replace data of particle prisoner at the index idx with particle
  !!
  subroutine replace_particle(self, p, idx)
    class(particleDungeon), intent(inout) :: self
    class(particle), intent(in)           :: p
    integer(shortInt), intent(in)         :: idx
    character(100),parameter :: Here = 'relplace_particle (particleDungeon_class.f90)'

    ! Protect agoinst out-of-bounds acces
    if( idx <= 0 .or. idx > self % pop ) then
      call fatalError(Here,'Out of bounds access with idx: '// numToChar(idx)// &
                           ' with particle population of: '// numToChar(self % pop))
    end if

    ! Load new particle
    self % prisoners(idx) = p

  end subroutine replace_particle

  !!
  !! Replace data of particle prisoner at the index idx with phaseCoords
  !!
  subroutine replace_particleState(self, p, idx)
    class(particleDungeon), intent(inout) :: self
    type(particleState), intent(in)       :: p
    integer(shortInt), intent(in)         :: idx
    character(100),parameter :: Here = 'relplace_particleState (particleDungeon_class.f90)'

    ! Protect agoinst out-of-bounds acces
    if( idx <= 0 .or. idx > self % pop ) then
      call fatalError(Here,'Out of bounds access with idx: '// numToChar(idx)// &
                           ' with particle population of: '// numToChar(self % pop))
    end if

    ! Load new particle
    self % prisoners(idx) = p

  end subroutine replace_particleState


  !!
  !! Copy particle from a location inside the dungeon
  !! Makes particle alive at exit
  !! Gives fatalError if requested index is 0, -ve or above current population
  !!
  subroutine copy(self, p, idx)
    class(particleDungeon), intent(in) :: self
    type(particle), intent(inout)      :: p
    integer(shortInt), intent(in)      :: idx
    character(100), parameter :: Here = 'copy (particleDungeon_class.f90)'

    ! Protect agoinst out-of-bounds acces
    if( idx <= 0 .or. idx > self % pop ) then
      call fatalError(Here,'Out of bounds acces with idx: '// numToChar(idx)// &
                           ' with particle population of: '// numToChar(self % pop))
    end if

    ! Load data into the particle
    p = self % prisoners(idx)
    p % isDead = .false.

  end subroutine copy

  !!
  !! Return particleState from a location inside the dungeon
  !! Gives fatalError if requested index is 0, -ve or above current population
  !!
  function get(self, idx) result(state)
    class(particleDungeon), intent(in) :: self
    integer(shortInt), intent(in)      :: idx
    type(particleState)                :: state
    character(100), parameter :: Here = 'get (particleDungeon_class.f90)'

    ! Protect agoinst out-of-bounds acces
    if( idx <= 0 .or. idx > self % pop ) then
      call fatalError(Here,'Out of bounds acces with idx: '// numToChar(idx)// &
                           ' with particle population of: '// numToChar(self % pop))
    end if

    ! Explicit copy. Will be changed soon
    state = self % prisoners(idx)

  end function get

  !!
  !! Returns .true. if dungeon is empty
  !!
  function isEmpty(self) result(isIt)
    class(particleDungeon), intent(in) :: self
    logical(defBool)                   :: isIt

    isIt = (self % pop == 0)

  end function isEmpty

  !!
  !! Normalise total weight of the particles in the dungeon to match provided value
  !!
  subroutine normWeight(self,totWgt)
    class(particleDungeon), intent(inout) :: self
    real(defReal), intent(in)             :: totWgt
    real(defReal)                         :: factor

    ! Behold the glory of Fortran! Normalisation of weights in two lines
    factor = totWgt / sum(self % prisoners(1:self % pop) % wgt)
    self % prisoners % wgt = self % prisoners % wgt * factor

  end subroutine normWeight

  !!
  !! Normalise total number of particles in the dungeon to match the provided number
  !! Randomly duplicate or remove particles to match the number
  !! Does not take weight of a particle into account!
  !!
  subroutine normSize(self,N,rand)
    class(particleDungeon), intent(inout) :: self
    integer(shortInt), intent(in)         :: N
    class(RNG), intent(inout)             :: rand
    integer(shortInt)                     :: excessP
    integer(shortInt)                     :: i, idx
    character(100), parameter :: Here = 'normSize (particleDungeon_class.f90)'

    ! Protect against invalid N
    if( N > size(self % prisoners)) then
      call fatalError(Here,'Requested size: '//numToChar(N) //&
                           'is greather then max size: '//numToChar(size(self % prisoners)))
    else if ( N <= 0 ) then
      call fatalError(Here,'Requested size: '//numToChar(N) //' is not +ve')
    end if

    ! Calculate excess particles to be removed
    excessP = self % pop - N

    if (excessP > 0 ) then ! Reduce population with reservoir sampling
      do i=N,self % pop
        ! Select new index. Copy data if it is in the safe zone (<= N).
        idx = int(i * rand % get())+1
        if (idx <= N) then
          self % prisoners(idx) = self % prisoners(i)
        end if
      end do
      self % pop = N

    else if (excessP < 0) then ! Clone randomly selected particles
      do i = self % pop, N
        idx = int(self % pop * rand % get()) + 1
        self % prisoners(i) = self % prisoners(idx)
      end do
      self % pop = N

    end if

  end subroutine normSize

  !!
  !! Reduce size of particle dungeon to a size N, while maintaining total weight
  !! and reducing teleportation error
  !!
  !! Rather than simply calling normSize(N) followed by normWeight(prevWeight), this
  !! subroutine combines 2 random particles of the same type into a single particle,
  !! with a new position based on a weighted average of the previous positions
  !!
  !! Finding the nearest particle would be better but much more computationally intensive,
  !! may be doable in parallel
  !!
  subroutine reduceSize(self, N, rand)
    class(particleDungeon), intent(inout) :: self
    integer(shortInt), intent(in)         :: N
    class(RNG), intent(inout)             :: rand
    integer(shortInt)                     :: randIdx1, randIdx2, loops, loops2
    type(particle)                        :: p1, p2, p3
    real(defReal), dimension(3)           :: rNew, r1, r2, r12
    real(defReal)                         :: dist
    character(100), parameter :: Here ='reduceSize (particleDungeon_class.f90)'

    print *, "REDUCE", self % pop, N

    ! Protect against invalid N
    if(N > self % pop) then
      call fatalError(Here,'Requested size: '//numToChar(N) //&
                           'is greather then max size: '//numToChar(size(self % prisoners)))
    else if (N <= 0) then
      call fatalError(Here,'Requested size: '//numToChar(N) //' is not +ve')
    end if

    ! Protect against infinite loop
    loops = 0

    reduce:do

      loops = loops + 1
      if(loops >= 50*self % pop) call fatalError(Here, 'Potentially infinite loop')

      ! Obtain random particles from dungeon
      randIdx1 = ceiling(rand % get() * self % pop)
      call self % copy(p1, randIdx1)
      r1 = p1 % rGlobal()

      ! Obtain random particle of the same type
      loops2 = 0
      sample:do
        randIdx2 = ceiling(rand % get() * self % pop)
        if (randIdx2 == randIdx1 .or. randIdx2 == self % pop) cycle sample
        call self % copy(p2, randIdx2)
        r2 = p2 % rGlobal()
        r12 = r2 - r1
        dist = sqrt(r12(1)**2 + r12(2)**2 + r12(3)**2)
        if (p2 % type == p1 % type .and. dist <= 0.2 .and. r1(1) <= 0.5) exit sample
        ! If too many failed samples, resample p1
        if (loops2 >= 0.5*self % pop) cycle reduce
        loops2 = loops2 + 1
      end do sample

      ! Combine positions and weights
      rNew = (r1*p1 % w + r2*p2 % w) / (p1 % w + p2 % w)
      call p1 % teleport(rNew)
      p1 % w = p1 % w + p2 % w
      call self % replace(p1, randIdx1)

      ! Overwrite p2 and reduce size
      call self % release(p3)
      call self % replace(p3, randIdx2)

      if(self % pop == N) exit reduce

      if(self % pop < N) call fatalError(Here, 'Uh oh, dungeon size somehow went below target')

    end do reduce

  end subroutine reduceSize

  !!
  !! N = max in each cell
  !!
  subroutine reduceSize2(self, N, Nmats, geom, rand, idxArray, toKeep)
    class(particleDungeon), intent(inout)          :: self
    integer(shortInt), intent(in)                  :: N
    integer(shortInt), intent(in)                  :: Nmats
    class(geometry), intent(inout)                 :: geom
    class(RNG), intent(inout)                      :: rand
    integer(shortInt), dimension(:,:), pointer, intent(inout) :: idxArray
    integer(shortInt), dimension(:), pointer, intent(inout) :: toKeep
    integer(shortInt)                              :: matIdx, pIdx, pIdx2, closeIdx, num
    integer(shortInt)                              :: i, j, j_dec, k
    real(defReal), dimension(3)                    :: r1, r2
    real(defReal)                                  :: dist, minDist
    character(100), parameter :: Here = 'reduceSize2 (particleDungeon_class.f90)'

    idxArray = 0
    toKeep = 0

    ! Generate array with first row as N_particles in each mat, and subsequent rows
    ! containing dungeon idx of each particle in that mat
    do i = 1, self % pop
      !call geom % whatIsAt(matIdx, matIdx, self % prisoners(i) % r)
      if (self % prisoners(i) % type == P_MATERIAL) then
        matIdx = self % prisoners(i) % matIdx
        num = idxArray(1,matIdx) + 1
        idxArray(1,matIdx) = num
        idxArray(num+1,matIdx) = i
      else if (self % prisoners(i) % type /= P_PHOTON) then
        call fatalError(Here,'Incorrect particle type')
      end if
    end do

    ! Determine which mats need populations reduced
    do i = 1, Nmats
      num = idxArray(1,i)
      if (num > N) then
        print *, 'Reducing mat '//numToChar(i)//' from '//numToChar(num)//' to '//numToChar(N)
        ! Sample particles to keep
        do j = 1, N
          toKeep(j) = idxArray(j+1,i)
        end do
        ! Loop through particles to be removed
        do j = N+1, num
          j_dec = num-j+N+1
          pIdx = idxArray(j_dec+1,i)
          r1 = self % prisoners(pIdx) % r
          ! Find closest particle in particles to keep
          minDist = INF
          do k = 1, N
            pIdx2 = toKeep(k)
            r2 = self % prisoners(pIdx2) % r - r1
            dist = sqrt(r2(1)**2 + r2(2)**2 + r2(3)**2)
            if (dist < minDist) then
              minDist  = dist
              closeIdx = pIdx2
            end if
          end do
          ! Combine particle with closest particle to keep
          call self % combine(pIdx, closeIdx)
        end do
      end if
    end do

  end subroutine reduceSize2

  !!
  !!
  !!
  !! Args:
  !!   N          => Maximum number of particles in each region
  !!   Nmats      => Number of material regions
  !!   emptyArray => Pointer to an array of size (2, system limit) to avoid allocating every time
  !!
  subroutine reduceSize3(self, N, Nmats, emptyArray)
    class(particleDungeon), intent(inout) :: self
    integer(shortInt), intent(in)         :: N
    integer(shortInt), intent(in)         :: Nmats
    integer(shortInt), dimension(:,:), intent(in), pointer :: emptyArray
    !integer(shortInt), dimension(:), intent(in), pointer :: toKeep
    integer(shortInt), dimension(:), pointer :: idxArray, toKeep
    integer(shortInt)                     :: i, j, idxKeep, idxRemove
    real(defReal), dimension(3)           :: r
    real(defReal)                         :: minDist

    ! Initialise arrays and pointers
    emptyArray = 0
    idxArray   => emptyArray(1, 1:size(emptyArray,1))
    toKeep     => emptyArray(2, 1:size(emptyArray,1))

    ! Store particle matIdx in array for easy access
    idxArray(1:self % pop) = self % prisoners(1:self % pop) % matIdx

    ! Only consider material particles
    idxArray = idxArray * merge(1, 0, self % prisoners(1:self % pop) % type == P_MATERIAL)

    do i=1, Nmats

      ! Determine if population needs to be reduced
      if (count(idxArray == i) > N) then
        ! Set toKeep array to be 1 for mat particles in material i and 0 otherwise
        toKeep = merge(1, 0, idxArray == i)
        do j=1, N
          ! Select particles being kept and increase flag from 1 to 2
          toKeep(findloc(toKeep, 1, 1)) = 2
        end do
      end if

      reduce:do
        ! Exit if material population does not need to be reduced
        if (count(toKeep == 1) > 0) exit reduce

        ! Select particle to be removed
        idxRemove = findloc(toKeep, 1, 1)
        r = self % prisoners(idxRemove) % r

        ! Find minimum distance to a particle being kept
        minDist = INF
        do j=1, size(toKeep)
          if (toKeep(j) == 2) minDist = min(minDist, self % prisoners(j) % getDistance(r))
        end do
        idxKeep = findloc(self % prisoners(1:self % pop), minDist, 1)

        ! Combine particles
        call self % combine(idxKeep, idxRemove)

      end do reduce

    end do


  end subroutine reduceSize3


  !!
  !! Combine two particles in the dungeon, and reduce dungeon size by 1
  !!
  !! Particle at idx1 remains, and is moved to a position that is the energy-weighted average
  !! of the two original positions. Its new energy is the sum of the two original energies.
  !! To reduce dungeon size, particle at position self % pop is copied into position idx2.
  !!
  subroutine combine(self, idx1, idx2)
    class(particleDungeon), intent(inout) :: self
    integer(shortInt), intent(in)         :: idx1
    integer(shortInt), intent(in)         :: idx2
    type(particle)                        :: p1, p2, p3
    real(defReal), dimension(3)           :: r1, r2, rNew

    ! Get initial particle data
    call self % copy(p1, idx1)
    call self % copy(p2, idx2)
    r1 = p1 % rGlobal()
    r2 = p2 % rGlobal()

    ! Move to new combined position
    rNew = (r1*p1 % w + r2*p2 % w) / (p1 % w + p2 % w)
    call p1 % teleport(rNew)

    ! Combine weights and overwrite particle
    p1 % w = p1 % w + p2 % w
    call self % replace(p1, idx1)

    ! Release top particle and place at idx2
    call self % release(p3)
    if (idx2 /= self % pop) call self % replace(p3, idx2)

  end subroutine combine

  !!
  !! Kill or particles in the dungeon
  !!
  pure subroutine cleanPop(self)
    class(particleDungeon), intent(inout) :: self

    self % pop = 0

  end subroutine cleanPop

  !!
  !! Returns number of particles in the dungeon
  !!
  function popSize(self) result(pop)
    class(particleDungeon), intent(in) :: self
    integer(shortInt)                  :: pop

    pop = self % pop

  end function popSize

  !!
  !! Returns total population weight
  !!
  function popWeight(self) result(wgt)
    class(particleDungeon), intent(in) :: self
    real(defReal)                      :: wgt

    wgt = sum( self % prisoners(1:self % pop) % wgt )

  end function popWeight

  !!
  !! Set size of the dungeon to n
  !!
  !! Sets population to arbitrary size n
  !! All stored particles revert to default initialisation state
  !!
  !! Args:
  !!   n [in] -> Requested size of the population
  !!
  !! Errors:
  !!   fatalError if n is invalid (not +ve)
  !!
  subroutine setSize(self, n)
    class(particleDungeon), intent(inout) :: self
    integer(shortInt), intent(in)         :: n
    character(100), parameter :: Here = 'setSize (particleDungeon_class.f90)'

    if (n <= 0) call fatalError(Here, 'Requested population is not +ve: '//numToChar(n))

    ! Set population
    self % pop = n

    ! Make shure enough space is avaliable
    if (allocated(self % prisoners)) then
      if (size(self % prisoners) < n) then
        deallocate(self % prisoners)
        allocate(self % prisoners(n))
      end if

    else
      allocate(self % prisoners(n))
    end if

    ! Set known (default) state to all particles
    call self % prisoners % kill()

  end subroutine setSize

  !!
  !! Prints the position of fission sites to a file
  !! Used initially for looking at clustering
  !!
  subroutine printToFile(self, name)
    class(particleDungeon), intent(in) :: self
    character(*), intent(in)           :: name
    character(256)                     :: filename
    integer(shortInt)                  :: i

    filename = trim(name)//'.txt'
    open(unit = 10, file = filename)

    ! Print out each particle co-ordinate
    do i = 1, self % pop
      write(10,'(8A)') numToChar(self % prisoners(i) % r), &
                       numToChar(self % prisoners(i) % dir), &
                       numToChar(self % prisoners(i) % E), &
                       numToChar(self % prisoners(i) % G), &
                       numToChar(self % prisoners(i) % matIdx)
    end do

    ! Close the file
    close(10)

  end subroutine printToFile

  !!
  !! Prints given property of particles to screen
  !!
  !! Args:
  !!   prop  [in] -> Particle property to be displayed
  !!   nMax  [in] -> Maximum number of particles displayed
  !!   total [in] -> Optional, if True then sum contributions of particles
  !!                  and print for total
  !!
  !! Errors:
  !!   fatalError if prop is invalid
  !!
  subroutine printToScreen(self, prop, nMax)
    class(particleDungeon), intent(in)     :: self
    character(*), intent(in)               :: prop
    integer(shortInt), intent(in)          :: nMax
    integer(shortInt)                      :: i,iMax
    character(100), parameter :: Here = 'printToScreen (particleDungeon_class.f90)'

    character(nameLen), dimension(*), parameter :: AVAILABLE_props = [ 'r     ',&
                                                                       'dir   ',&
                                                                       'matIdx',&
                                                                       'E     ',&
                                                                       'G     ',&
                                                                       'wgt   ',&
                                                                       'time  ',&
                                                                       'pop   ']

    print *, 'Number in dungeon =', self % pop

    ! Number of particles to be printed
    iMax = min(nMax, self % pop)

    ! Print desired quantities
    select case(prop)
      case('r')
        print *, '**          ** Position **          **'
        do i = 1, iMax
          print *, i,numToChar(self % prisoners(i) % r)
        end do

      case('dir')
        print *, '**          ** Direction **          **'
        do i = 1, iMax
          print *, i,numToChar(self % prisoners(i) % dir)
        end do

      case('matIdx')
        print *, '**          ** matIdx **          **'
        do i = 1, iMax
          print *, i,numToChar(self % prisoners(i) % matIdx)
        end do

      case('E')
        print *, '**          ** Energy **          **'
        do i = 1, iMax
          print *, i,numToChar(self % prisoners(i) % E)
        end do
     
      case('G')
        print *, '**          ** Group **          **'
        do i = 1, iMax
          print *, i,numToChar(self % prisoners(i) % G)
        end do

      case('wgt')
        print *, '**          ** Weight **          **'
        do i = 1, iMax
          print *, i,numToChar(self % prisoners(i) % wgt)
        end do

      case('time')
        print *, '**          ** Time **          **'
        do i = 1, iMax
          print *, i,numToChar(self % prisoners(i) % time)
        end do

      case('pop')
        ! Do nothing, pop already printed above

      case default
        print *, AVAILABLE_props
        call fatalError(Here, 'Unrecognised particle property : ' // trim(prop))

    end select

  end subroutine printToScreen
    

end module particleDungeon_class
