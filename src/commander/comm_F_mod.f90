module comm_F_mod
  use comm_comp_mod
  use comm_param_mod
  use comm_map_mod
  use comm_bp_mod
  use comm_F_int_mod
  use comm_F_int_1D_mod
  implicit none

  private
  public comm_F

  type :: comm_F
     ! Linked list variables
     class(comm_F), pointer :: nextLink => null()
     class(comm_F), pointer :: prevLink => null()

     ! Data variables
     class(comm_bp),    pointer :: bp
     class(comm_comp),  pointer :: c
     class(comm_map),   pointer :: F_diag
     class(comm_F_int), pointer :: F_int

     real(dp)                   :: checksum
   contains
     ! Linked list procedures
     procedure :: next    ! get the link after this link
     procedure :: prev    ! get the link before this link
     procedure :: setNext ! set the link after this link
     procedure :: add     ! add new link at the end

     ! Data procedures
     procedure :: F          => matmulF
     procedure :: update     => updateTheta
     procedure :: writeFITS 
  end type comm_F

  interface comm_F
     procedure constructor
  end interface comm_F

contains

  !**************************************************
  !             Routine definitions
  !**************************************************
  function constructor(info, comp, bp)
    implicit none
    class(comm_mapinfo), intent(in), target :: info
    class(comm_comp),    intent(in), target :: comp
    class(comm_bp),      intent(in), target :: bp
    class(comm_F),       pointer            :: constructor

    ! General parameters
    allocate(constructor)
    constructor%c        => comp
    constructor%bp       => bp
    constructor%F_diag   => comm_map(info)
    constructor%checksum =  -1.d30
    
  end function constructor

  ! Return map_out = F * map
  subroutine matmulF(self, map, res)
    implicit none
    class(comm_F),   intent(in)     :: self
    class(comm_map), intent(in)     :: map
    class(comm_map), intent(inout)  :: res
    res%map = self%F_diag%map * map%map
  end subroutine matmulF

  ! id = 1 => common {T,Q,U}
  ! id = 2 => T + common {Q,U}
  ! id = 3 => T + Q + U
  subroutine updateTheta(self, theta, id)
    implicit none
    class(comm_F),                 intent(inout) :: self
    class(comm_map), dimension(:), intent(in)    :: theta  ! Parameter maps; both alm and map
    integer(i4b),                  intent(in)    :: id

    integer(i4b) :: i, j, p
    real(dp)     :: checksum, t(self%c%npar)

    checksum = 0.d0
    do i = 1, self%c%npar
       checksum = checksum + sum(abs(theta(i)%alm))
    end do
    if (checksum == self%checksum) return

    ! Update with new parameter set
    self%checksum = checksum

    ! Temperature
    do p = 0, self%F_diag%info%np-1
       do j = 1, self%c%npar
          t(j) = theta(j)%map(p,1)
       end do
       self%F_diag%map(p,1) = self%F_int%eval(t)
    end do

    if (self%F_diag%info%nmaps == 3) then
       ! Stokes Q
       if (id > 1) then
          do p = 0, self%F_diag%info%np-1
             do j = 1, self%c%npar
                t(j) = theta(j)%map(p,2)
             end do
             self%F_diag%map(p,2) = self%F_int%eval(t)
          end do
       else
          self%F_diag%map(:,2) = self%F_diag%map(:,1)
       end if
       
       ! Stokes U
       if (id > 2) then
          do p = 0, self%F_diag%info%np-1
             do j = 1, self%c%npar
                t(j) = theta(j)%map(p,2)
             end do
             self%F_diag%map(p,3) = self%F_int%eval(t)
          end do
       else
          self%F_diag%map(:,3) = self%F_diag%map(:,2)
       end if
    end if

  end subroutine updateTheta
  
  subroutine writeFITS(self, filename)
    implicit none
    class(comm_F),    intent(in) :: self
    character(len=*), intent(in) :: filename
    call self%F_diag%writeFITS(filename)
  end subroutine writeFITS
  
  function next(self)
    class(comm_F) :: self
    class(comm_F), pointer :: next
    next => self%nextLink
  end function next

  function prev(self)
    class(comm_F) :: self
    class(comm_F), pointer :: prev
    prev => self%prevLink
  end function prev
  
  subroutine setNext(self,next)
    class(comm_F) :: self
    class(comm_F), pointer :: next
    self%nextLink => next
  end subroutine setNext

  subroutine add(self,link)
    class(comm_F)         :: self
    class(comm_F), target :: link

    class(comm_F), pointer :: c
    
    c => self%nextLink
    do while (associated(c%nextLink))
       c => c%nextLink
    end do
    link%prevLink => c
    c%nextLink    => link
  end subroutine add  
  
end module comm_F_mod
