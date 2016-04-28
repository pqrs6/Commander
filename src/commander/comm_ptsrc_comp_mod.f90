module comm_ptsrc_comp_mod
  use math_tools
  use comm_param_mod
  use comm_comp_mod
  use comm_F_int_mod
  use comm_F_int_0D_mod
  use comm_F_int_2D_mod
  use comm_data_mod
  use pix_tools
  use comm_hdf_mod
  use comm_cr_utils
  use comm_cr_precond_mod
  use locate_mod
  use spline_1D_mod
  implicit none

  private
  public comm_ptsrc_comp, initPtsrcPrecond, updatePtsrcPrecond, applyPtsrcPrecond

  !**************************************************
  !            Compact object class
  !**************************************************
  type Tnu
     integer(i4b) :: nside, np, nmaps
     integer(i4b), allocatable, dimension(:,:) :: pix     ! Pixel list, both absolute and relative
     real(dp),     allocatable, dimension(:,:) :: map     ! (0:np-1,nmaps)
     real(dp),     allocatable, dimension(:)   :: F       ! Mixing matrix (nmaps)
     real(dp),     allocatable, dimension(:)   :: Omega_b ! Solid angle (nmaps
  end type Tnu

  type ptsrc
     character(len=512) :: outprefix
     character(len=512) :: id
     real(dp)           :: glon, glat, f_beam, vec(3)
     type(Tnu), allocatable, dimension(:)   :: T      ! Spatial template (nband)
     real(dp),  allocatable, dimension(:,:) :: theta  ! Spectral parameters (npar,nmaps)
  end type ptsrc
  
  type, extends (comm_comp) :: comm_ptsrc_comp
     character(len=512) :: outprefix
     real(dp)           :: cg_scale
     integer(i4b)       :: nside, nsrc, ncr_tot
     real(dp),        allocatable, dimension(:,:) :: x      ! Amplitudes (sum(nsrc),nmaps)
     type(F_int_ptr), allocatable, dimension(:)   :: F_int  ! SED integrator (numband)
     type(ptsrc),     allocatable, dimension(:)   :: src    ! Source template (nsrc)
   contains
     procedure :: dumpFITS => dumpPtsrcToFITS
     procedure :: getBand  => evalPtsrcBand
     procedure :: projectBand  => projectPtsrcBand
     procedure :: updateF
     procedure :: S => evalSED
     procedure :: getScale
     procedure :: initHDF       => initPtsrcHDF
     procedure :: sampleSpecInd => samplePtsrcSpecInd
  end type comm_ptsrc_comp

  interface comm_ptsrc_comp
     procedure constructor
  end interface comm_ptsrc_comp

  type ptsrc_ptr
     class(comm_ptsrc_comp), pointer :: p
  end type ptsrc_ptr
  
  integer(i4b) :: ncomp_pre    =   0
  integer(i4b) :: npre         =   0
  integer(i4b) :: nmaps_pre    =  -1
  integer(i4b) :: comm_pre     =  -1
  integer(i4b) :: myid_pre     =  -1
  integer(i4b) :: numprocs_pre =  -1
  class(ptsrc_ptr), allocatable, dimension(:) :: ptsrcComps
  
contains

  function constructor(cpar, id, id_abs)
    implicit none
    class(comm_params),       intent(in) :: cpar
    integer(i4b),             intent(in) :: id, id_abs
    class(comm_ptsrc_comp),   pointer    :: constructor

    integer(i4b) :: i, j, k, nlist, npix, listpix(0:10000-1), hits(10000)
    real(dp)     :: vec0(3), vec(3), r
    
    ! General parameters
    allocate(constructor)

    ! Initialize general parameters
    comm_pre              = cpar%comm_chain
    myid_pre              = cpar%myid
    numprocs_pre          = cpar%numprocs_chain
    constructor%class     = cpar%cs_class(id_abs)
    constructor%type      = cpar%cs_type(id_abs)
    constructor%label     = cpar%cs_label(id_abs)
    constructor%id        = id
    constructor%nmaps     = 1; if (cpar%cs_polarization(id_abs)) constructor%nmaps = 3
    constructor%nu_ref    = cpar%cs_nu_ref(id_abs)
    constructor%nside     = cpar%cs_nside(id_abs)
    constructor%outprefix = trim(cpar%cs_label(id_abs))
    constructor%cg_scale  = cpar%cs_cg_scale(id_abs)
    allocate(constructor%poltype(1))
    constructor%poltype   = cpar%cs_poltype(1,id_abs)
    constructor%myid      = cpar%myid
    constructor%comm      = cpar%comm_chain
    constructor%numprocs  = cpar%numprocs_chain
    ncomp_pre             = ncomp_pre + 1

    ! Initialize frequency scaling parameters
    allocate(constructor%F_int(numband))
    select case (trim(constructor%type))
    case ("radio")
       constructor%npar = 2   ! (alpha, beta)
       allocate(constructor%p_uni(2,constructor%npar), constructor%p_gauss(2,constructor%npar))
       allocate(constructor%theta_def(constructor%npar))
       constructor%p_uni     = cpar%cs_p_uni(id_abs,:,:)
       constructor%p_gauss   = cpar%cs_p_gauss(id_abs,:,:)
       constructor%theta_def = cpar%cs_theta_def(1:2,id_abs)
       do i = 1, numband
          constructor%F_int(i)%p => comm_F_int_2D(constructor, data(i)%bp)
       end do
    case ("fir")
       constructor%npar = 2   ! (beta, T_d)
       allocate(constructor%p_uni(2,constructor%npar), constructor%p_gauss(2,constructor%npar))
       allocate(constructor%theta_def(constructor%npar))
       constructor%p_uni     = cpar%cs_p_uni(id_abs,:,:)
       constructor%p_gauss   = cpar%cs_p_gauss(id_abs,:,:)
       constructor%theta_def = cpar%cs_theta_def(1:2,id_abs)
       do i = 1, numband
          constructor%F_int(i)%p => comm_F_int_2D(constructor, data(i)%bp)
       end do
    case ("sz")
       constructor%npar = 0   ! (none)
       do i = 1, numband
          constructor%F_int(i)%p => comm_F_int_0D(constructor, data(i)%bp)
       end do
    case default
       call report_error("Unknown point source model: " // trim(constructor%type))
    end select

    ! Read and allocate source structures
    call read_sources(constructor, cpar, id, id_abs)

    ! Update mixing matrix
    call constructor%updateF

  end function constructor



  subroutine updateF(self, beta)
    implicit none
    class(comm_ptsrc_comp),                   intent(inout)        :: self
    real(dp),               dimension(:,:,:), intent(in), optional :: beta  ! (npar,nmaps,nsrc)

    integer(i4b) :: i, j
    
    do j = 1, self%nsrc
       if (present(beta)) then
          self%src(j)%theta = beta(:,:,j)
       else
          do i = 1, self%nmaps
             self%src(j)%theta(:,i) = self%theta_def
          end do
       end if
       do i = 1, numband
          ! Temperature
          self%src(j)%T(i)%F(1) = &
               & self%F_int(i)%p%eval(self%src(j)%theta(:,1)) * data(i)%gain * self%cg_scale

          ! Polarization
          if (self%nmaps == 3) then
             ! Stokes Q
             if (self%poltype(1) < 2) then
                self%src(j)%T(i)%F(2) = self%src(j)%T(i)%F(1)
             else
                self%src(j)%T(i)%F(2) = &
                     & self%F_int(i)%p%eval(self%src(j)%theta(:,2)) * data(i)%gain * self%cg_scale
             end if
          
             ! Stokes U
             if (self%poltype(1) < 3) then
                self%src(j)%T(i)%F(3) = self%src(j)%T(i)%F(2)
             else
                self%src(j)%T(i)%F(3) = &
                     & self%F_int(i)%p%eval(self%src(j)%theta(:,3)) * data(i)%gain * self%cg_scale
             end if
          end if
       end do
    end do
    
  end subroutine updateF

  function evalSED(self, nu, band, theta)
    class(comm_ptsrc_comp),    intent(in)           :: self
    real(dp),                  intent(in), optional :: nu
    integer(i4b),              intent(in), optional :: band
    real(dp), dimension(1:),   intent(in), optional :: theta
    real(dp)                                        :: evalSED

    real(dp) :: x
    
    select case (trim(self%type))
    case ("radio")
       !evalSED = exp(theta(1) * (nu/self%nu_ref) + theta(2) * (log(nu/self%nu_ref))**2) * &
       !     & (self%nu_ref/nu)**2
       evalSED = (self%nu_ref/nu)**(2.d0+theta(1)) 
    case ("fir")
       x = h/(k_B*theta(2))
       evalSED = (exp(x*self%nu_ref)-1.d0)/(exp(x*nu)-1.d0) * (nu/self%nu_ref)**(theta(1)+1.d0)
    case ("sz")
       evalSED = 0.d0
       call report_error('SZ not implemented yet')
    end select
    
  end function evalSED

  function evalPtsrcBand(self, band, amp_in, pix, alm_out)
    implicit none
    class(comm_ptsrc_comp),                       intent(in)            :: self
    integer(i4b),                                 intent(in)            :: band
    integer(i4b),    dimension(:),   allocatable, intent(out), optional :: pix
    real(dp),        dimension(:,:),              intent(in),  optional :: amp_in
    logical(lgt),                                 intent(in),  optional :: alm_out
    real(dp),        dimension(:,:), allocatable                        :: evalPtsrcBand

    integer(i4b) :: i, j, p, q, ierr
    real(dp)     :: a
    real(dp), allocatable, dimension(:,:) :: amp

    if (.not. allocated(evalPtsrcBand)) &
         & allocate(evalPtsrcBand(0:data(band)%info%np-1,data(band)%info%nmaps))

    allocate(amp(self%nsrc,self%nmaps))
    if (self%myid == 0) then
       if (present(amp_in)) then
          amp = amp_in
       else
          amp = self%x
       end if
    end if
    call mpi_bcast(amp, size(amp), MPI_DOUBLE_PRECISION, 0, self%comm, ierr)

    ! Loop over sources
    evalPtsrcBand = 0.d0
    do i = 1, self%nsrc
       do j = 1, self%src(i)%T(band)%nmaps
          ! Scale to correct frequency through multiplication with mixing matrix
          a = self%getScale(band,i,j) * self%src(i)%T(band)%F(j) *  amp(i,j)
          
          ! Project with beam
          do q = 1, self%src(i)%T(band)%np
             p = self%src(i)%T(band)%pix(q,1)
             evalPtsrcBand(p,j) = evalPtsrcBand(p,j) + a * self%src(i)%T(band)%map(q,j)
          end do
       end do
    end do

    if (allocated(amp)) deallocate(amp)
    
  end function evalPtsrcBand
  
  ! Return component projected from map
  function projectPtsrcBand(self, band, map, alm_in)
    implicit none
    class(comm_ptsrc_comp),                       intent(in)            :: self
    integer(i4b),                                 intent(in)            :: band
    class(comm_map),                              intent(in)            :: map
    logical(lgt),                                 intent(in), optional  :: alm_in
    real(dp),        dimension(:,:), allocatable                        :: projectPtsrcBand

    integer(i4b) :: i, j, q, p, ierr
    real(dp)     :: val
    real(dp), allocatable, dimension(:,:) :: amp, amp2
    
    if (.not. allocated(projectPtsrcBand)) &
         & allocate(projectPtsrcBand(self%nsrc,self%nmaps))

    ! Loop over sources
    allocate(amp(self%nsrc,self%nmaps), amp2(self%nsrc,self%nmaps))
    amp = 0.d0
    do i = 1, self%nsrc
       do j = 1, self%src(i)%T(band)%nmaps
          val = 0.d0
          do q = 1, self%src(i)%T(band)%np
             p   = self%src(i)%T(band)%pix(q,1)
             val = val + self%src(i)%T(band)%map(q,j) * map%map(p,j)
          end do

          ! Scale to correct frequency through multiplication with mixing matrix
          val = self%getScale(band,i,j) * self%src(i)%T(band)%F(j) * val

          ! Return value
          amp(i,j) = val
       end do
    end do

    call mpi_reduce(amp, amp2, size(amp2), MPI_DOUBLE_PRECISION, MPI_SUM, 0, self%comm, ierr)
    if (self%myid == 0) projectPtsrcBand = amp2

    deallocate(amp,amp2)
    
  end function projectPtsrcBand
  
  ! Dump current sample to HEALPix FITS file
  subroutine dumpPtsrcToFITS(self, iter, chainfile, output_hdf, postfix, dir)
    class(comm_ptsrc_comp),                  intent(in)           :: self
    integer(i4b),                            intent(in)           :: iter
    type(hdf_file),                          intent(in)           :: chainfile
    logical(lgt),                            intent(in)           :: output_hdf
    character(len=*),                        intent(in)           :: postfix
    character(len=*),                        intent(in)           :: dir

    integer(i4b)       :: i, j, l, m, ierr, unit, ind(1)
    real(dp)           :: vals(10)
    logical(lgt)       :: exist, first_call = .true.
    character(len=6)   :: itext
    character(len=512) :: filename, path
    class(comm_map), pointer :: map
    real(dp), allocatable, dimension(:,:,:) :: theta

    ! Output point source maps for each frequency
    do i = 1, numband
       map => comm_map(data(i)%info)
       map%map = self%getBand(i) * self%cg_scale
       filename = trim(self%label) // '_' // trim(data(i)%label) // '_' // trim(postfix) // '.fits'
       call map%writeFITS(trim(dir)//'/'//trim(filename))
       deallocate(map)
    end do

    ! Output catalog
    if (self%myid == 0) then
       if (output_hdf) then
          ! Output to HDF
          call int2string(iter, itext)
          path = trim(adjustl(itext))//'/'//trim(adjustl(self%label))          
          call create_hdf_group(chainfile, trim(adjustl(path)))
          call write_hdf(chainfile, trim(adjustl(path))//'/amp',   self%x*self%cg_scale)
          allocate(theta(self%nsrc,self%nmaps,self%npar))
          do i = 1, self%nsrc
             do j = 1, self%nmaps
                theta(i,j,:) = self%src(i)%theta(:,j)
             end do
          end do
          call write_hdf(chainfile, trim(adjustl(path))//'/specind', theta)
          deallocate(theta)
       end if
       
       unit     = getlun()
       filename = trim(self%label) // '_' // trim(postfix) // '.dat'
       open(unit,file=trim(dir)//'/'//trim(filename),recl=1024,status='replace')
       if (self%nmaps == 3) then
          if (trim(self%type) == 'radio') then
             write(unit,*) '# '
             write(unit,*) '# SED model type      = ', trim(self%type)
             write(unit,fmt='(a,f10.2,a)') ' # Reference frequency = ', self%nu_ref*1d-9, ' GHz'
             write(unit,*) '# '
             write(unit,*) '# Glon(deg) Glat(deg)     I(mJy)    alpha_I   beta_I   Q(mJy)  ' // &
                  & ' alpha_Q  beta_Q  U(mJy)  alpha_U  beta_U  ID'
          else if (trim(self%type) == 'fir') then
             write(unit,*) '# '
             write(unit,*) '# SED model type      = ', trim(self%type)
             write(unit,fmt='(a,f10.2,a)') ' # Reference frequency = ', self%nu_ref*1d-9, ' GHz'
             write(unit,*) '# '
             write(unit,*) '# Glon(deg) Glat(deg)     I(mJy)    beta_I      T_I   Q(mJy)  ' // &
                  & ' beta_Q     T_Q  U(mJy)  beta_U     T_U  ID'             
          end if
       else
          if (trim(self%type) == 'radio') then
             write(unit,*) '# '
             write(unit,*) '# SED model type      = ', trim(self%type)
             write(unit,fmt='(a,f10.2,a)') ' # Reference frequency = ', self%nu_ref*1d-9, ' GHz'
             write(unit,*) '# '
             write(unit,*) '# Glon(deg) Glat(deg)     I(mJy)    alpha_I   beta_I   ID'
          else if (trim(self%type) == 'fir') then
             write(unit,*) '# '
             write(unit,*) '# SED model type      = ', trim(self%type)
             write(unit,fmt='(a,f10.2,a)') ' # Reference frequency = ', self%nu_ref*1d-9, ' GHz'
             write(unit,*) '# '
             write(unit,*) '# Glon(deg) Glat(deg)     I(mJy)    beta_I      T_I   ID'
          end if
       end if
       do i = 1, self%nsrc
          if (self%nmaps == 3) then
             if (trim(self%type) == 'radio' .or. trim(self%type) == 'fir') then
                write(unit,fmt='(2f10.4,f16.3,2f8.3,f16.3,2f8.3,f16.3,2f8.3,2a)') &
                     & self%src(i)%glon*RAD2DEG, self%src(i)%glat*RAD2DEG, &
                     & self%x(i,1)*self%cg_scale, self%src(i)%theta(:,1), &
                     & self%x(i,2)*self%cg_scale, self%src(i)%theta(:,2), &
                     & self%x(i,3)*self%cg_scale, self%src(i)%theta(:,3), &
                     & '  ', trim(self%src(i)%id)
             end if
          else
             if (trim(self%type) == 'radio' .or. trim(self%type) == 'fir') then
                write(unit,fmt='(2f10.4,f16.3,2f8.3,2a)') &
                     & self%src(i)%glon*RAD2DEG, self%src(i)%glat*RAD2DEG, &
                     & self%x(i,1)*self%cg_scale, self%src(i)%theta(:,1), &
                     & '  ', trim(self%src(i)%id)
             end if
          end if
       end do
       close(unit)
    end if
    
  end subroutine dumpPtsrcToFITS

  ! Dump current sample to HEALPix FITS file
  subroutine initPtsrcHDF(self, cpar, hdffile, hdfpath)
    implicit none
    class(comm_ptsrc_comp),    intent(inout) :: self
    type(comm_params),         intent(in)    :: cpar    
    type(hdf_file),            intent(in)    :: hdffile
    character(len=*),          intent(in)    :: hdfpath

    integer(i4b)       :: i, j
    real(dp)           :: md(4)
    character(len=512) :: path
    real(dp), allocatable, dimension(:,:,:) :: theta

    path = trim(adjustl(hdfpath))//trim(adjustl(self%label)) // '/'
    if (self%myid == 0) then
       call read_hdf(hdffile, trim(adjustl(path))//'/amp', self%x)
       self%x = self%x/self%cg_scale
       
       allocate(theta(self%nsrc,self%nmaps,self%npar))
       call read_hdf(hdffile, trim(adjustl(path))//'/specind', theta)
       do i = 1, self%nsrc
          do j = 1, self%nmaps
             self%src(i)%theta(:,j) = theta(i,j,:) 
          end do
       end do
       deallocate(theta)
    end if
  end subroutine initPtsrcHDF

  subroutine read_sources(self, cpar, id, id_abs)
    implicit none
    class(comm_ptsrc_comp), intent(inout) :: self
    class(comm_params),     intent(in)    :: cpar
    integer(i4b),           intent(in)    :: id, id_abs

    integer(i4b)        :: unit, i, j, npar, nmaps, pix, nside, n
    real(dp)            :: glon, glat, nu_ref, dist, vec0(3), vec(3)
    logical(lgt)        :: pol, skip_src
    character(len=1024) :: line, filename, tempfile
    character(len=128)  :: id_ptsrc, flabel
    real(dp), allocatable, dimension(:)   :: amp
    real(dp), allocatable, dimension(:,:) :: beta

    unit = getlun()

    nmaps = 1; if (cpar%cs_polarization(id_abs)) nmaps = 3
    select case (trim(cpar%cs_type(id_abs)))
    case ("radio")
       npar = 2
    case ("fir")
       npar = 2
    case ("sz")
       npar = 0
    end select
    allocate(amp(nmaps), beta(npar,nmaps))

    ! Count number of valid sources
    open(unit,file=trim(cpar%datadir) // '/' // trim(cpar%cs_catalog(id_abs)),recl=1024)
    self%nsrc    = 0
    self%ncr     = 0
    self%ncr_tot = 0
    do while (.true.)
       read(unit,'(a)',end=1) line
       line = trim(line)
       if (line(1:1) == '#' .or. trim(line) == '') then
          cycle
       else
          self%nsrc    = self%nsrc + 1
          npre         = npre + 1
          nmaps_pre    = max(nmaps_pre, nmaps)
          self%ncr_tot = self%ncr_tot  + nmaps
          if (cpar%myid == 0) self%ncr  = self%ncr  + nmaps
       end if
    end do 
1   close(unit)

    if (self%nsrc == 0) call report_error('No valid sources in = ' // &
         & trim(trim(cpar%datadir) // '/' // trim(cpar%cs_catalog(id_abs))))
    
    ! Initialize point sources based on catalog information
    allocate(self%x(self%nsrc,self%nmaps), self%src(self%nsrc))
    open(unit,file=trim(cpar%datadir) // '/' // trim(cpar%cs_catalog(id_abs)),recl=1024)
    i = 0
    do while (.true.)
       read(unit,'(a)',end=2) line
       line = trim(line)
       if (line(1:1) == '#' .or. trim(line) == '') cycle
       read(line,*) glon, glat, amp, beta, id_ptsrc
       ! Check for too close neighbours
       skip_src = .false.
       call ang2vec(0.5d0*pi-glat*DEG2RAD, glon*DEG2RAD, vec)
       do j = 1, i
          call angdist(vec, self%src(j)%vec, dist)
          if (dist*RAD2DEG*60.d0 < cpar%cs_min_src_dist(id_abs)) then
             skip_src = .true.
             exit
          end if
       end do
       if (skip_src) then
          self%nsrc = self%nsrc-1
       else
          i                    = i+1
          allocate(self%src(i)%theta(self%npar,self%nmaps), self%src(i)%T(numband))
          self%src(i)%id       = id_ptsrc
          self%src(i)%glon     = glon * DEG2RAD
          self%src(i)%glat     = glat * DEG2RAD
          self%src(i)%theta    = beta
          self%x(i,:)          = amp / self%cg_scale
          self%src(i)%vec      = vec
       end if
    end do 
2   close(unit)


    ! Initialize beam templates
    tempfile = trim(cpar%datadir)//'/'//trim(cpar%cs_ptsrc_template(id_abs))
    do j = 1, self%nsrc
       if (mod(j,100) == 0 .and. self%myid == 0) &
            & write(*,fmt='(a,i6,a,i6)') '   Initializing src no. ', j, ' of ', self%nsrc
       do i = 1, numband
          self%src(j)%T(i)%nside   = data(i)%info%nside
          self%src(j)%T(i)%nmaps   = min(data(i)%info%nmaps, self%nmaps)
          allocate(self%src(j)%T(i)%F(self%src(j)%T(i)%nmaps))
          self%src(j)%T(i)%F       = 0.d0

          ! Get pixel space template; try precomputed templates first
          if (trim(cpar%cs_ptsrc_template(id_abs)) /= 'none' .and. &
               & .not.  cpar%cs_output_ptsrc_beam(id_abs)) then
             call read_febecop_beam(cpar, tempfile, data(i)%label, &
                  & self%src(j)%glon, self%src(j)%glat, i, self%src(j)%T(i))             
          else
             filename = trim(cpar%datadir)//'/'//trim(cpar%ds_btheta_file(i))
             n        = len(trim(adjustl(filename)))
             if (filename(n-2:n) == '.h5') then
                ! Read precomputed Febecop beam from HDF file
                call read_febecop_beam(cpar, filename, 'none', &
                     & self%src(j)%glon, self%src(j)%glat, i, self%src(j)%T(i))
             else if (trim(trim(cpar%ds_btheta_file(i))) == 'none') then
                ! Build template internally from b_l
                call compute_symmetric_beam(i, self%src(j)%glon, self%src(j)%glat, &
                     & self%src(j)%T(i), bl=data(i)%B%b_l)
             else if (filename(n-3:n) == '.dat' .or. filename(n-3:n) == '.txt') then
                ! Build template internally from b_l
                call compute_symmetric_beam(i, self%src(j)%glon, self%src(j)%glat, &
                     & self%src(j)%T(i), beamfile=filename)             
             else
                call report_error('Unsupported point source template = '//trim(filename))
             end if
          end if
       end do
    end do
    if (cpar%cs_output_ptsrc_beam(id_abs)) call dump_beams_to_hdf(self, tempfile)
    
  end subroutine read_sources


  subroutine read_febecop_beam(cpar, filename, label, glon, glat, band, T)
    implicit none
    class(comm_params), intent(in)    :: cpar
    character(len=*),   intent(in)    :: filename, label
    real(dp),           intent(in)    :: glon, glat
    integer(i4b),       intent(in)    :: band
    type(Tnu),          intent(inout) :: T

    integer(i4b)      :: i, j, n, pix, ext(1), ierr, m(1)
    character(len=128) :: itext
    type(hdf_file)    :: file
    integer(i4b), allocatable, dimension(:)   :: ind
    integer(i4b), allocatable, dimension(:,:) :: mypix
    real(dp),     allocatable, dimension(:,:) :: b, mybeam
    real(dp),     allocatable, dimension(:)   :: buffer

    if (myid_pre == 0) then
       ! Find center pixel number for current source
       call ang2pix_ring(T%nside, 0.5d0*pi-glat, glon, pix)

       ! Find number of pixels in beam
       write(itext,*) pix
       if (trim(label) /= 'none') itext = trim(label)//'/'//trim(adjustl(itext))
       call open_hdf_file(filename, file, 'r')
       call get_size_hdf(file, trim(adjustl(itext))//'/indices', ext)
       n = ext(1)

       ! Read full beam from file
       allocate(ind(n), b(n,T%nmaps), mypix(n,2), mybeam(n,T%nmaps))
       call read_hdf(file, trim(adjustl(itext))//'/indices', ind)
       call read_hdf(file, trim(adjustl(itext))//'/values',  b)
       call close_hdf_file(file)

       ! Distribute information
       call mpi_bcast(n,   1, MPI_INTEGER, 0, comm_pre, ierr)
    else
       call mpi_bcast(n, 1, MPI_INTEGER, 0, comm_pre, ierr)
       allocate(ind(n), b(n,T%nmaps), mypix(n,2), mybeam(n,T%nmaps))
    end if
    call mpi_bcast(ind, size(ind), MPI_INTEGER,          0, comm_pre, ierr)
    call mpi_bcast(b,   size(b),   MPI_DOUBLE_PRECISION, 0, comm_pre, ierr)

    ! Find number of pixels belonging to current processor
    T%np = 0
    i    = 1
    j    = locate(data(band)%info%pix, ind(i))
    if (j > 0) then
       do while (.true.)
          if (ind(i) == data(band)%info%pix(j)) then
             T%np            = T%np + 1
             mypix(T%np,1)   = j-1
             mypix(T%np,2)   = data(band)%info%pix(j)
             mybeam(T%np,:)  = b(i,:)
             i               = i+1
             j               = j+1
          else if (ind(i) < data(band)%info%pix(j)) then
             i               = i+1
          else
             j               = j+1
          end if
          if (i > n) exit
          if (j > data(band)%info%np) exit
       end do
    end if

    ! Store pixels that belong to current processor
    allocate(T%pix(T%np,2), T%map(T%np,T%nmaps), T%Omega_b(T%nmaps))
    T%pix = mypix(1:T%np,:)
    do i = 1, T%nmaps
       T%map(:,i)   = mybeam(1:T%np,i) / maxval(b(:,i))
       T%Omega_b(i) = sum(b(:,i))/maxval(b(:,i)) * 4.d0*pi/(12.d0*T%nside**2)
    end do

    deallocate(ind, b, mypix, mybeam)
    
  end subroutine read_febecop_beam

  subroutine dump_beams_to_hdf(self, filename)
    implicit none
    class(comm_ptsrc_comp), intent(in)  :: self
    character(len=*),       intent(in)  :: filename

    integer(i4b)   :: i, j, k, l, n, n_tot, m, p, ierr, nmaps, itmp, hdferr
    real(dp)       :: rtmp(3)
    logical(lgt)   :: exist
    type(hdf_file) :: file
    TYPE(h5o_info_t) :: object_info    
    character(len=128) :: itext
    integer(i4b), allocatable, dimension(:)   :: ind
    real(dp),     allocatable, dimension(:,:) :: beam
    integer(i4b), dimension(MPI_STATUS_SIZE) :: status

    inquire(file=trim(filename), exist=exist)
    if (exist) call report_error('Error: Ptsrc template file already exist = '//trim(filename))
    call mpi_barrier(comm_pre, ierr)

    if (myid_pre == 0) call open_hdf_file(filename, file, 'w')
    do k = 1, self%nsrc
       do i = 1, numband
          if (myid_pre == 0 .and. k == 1) &
               & call create_hdf_group(file, trim(adjustl(data(i)%label)))
          nmaps = self%src(k)%T(i)%nmaps
          call ang2pix_ring(data(i)%info%nside, 0.5d0*pi-self%src(k)%glat, self%src(k)%glon, p)
          write(itext,*) p
          itext = trim(adjustl(data(i)%label))//'/'//trim(adjustl(itext))
          if (myid_pre == 0) then
             call h5eset_auto_f(0, hdferr)
             call h5oget_info_by_name_f(file%filehandle, trim(adjustl(itext)), object_info, hdferr)
             if (hdferr == 0) call h5gunlink_f(file%filehandle, trim(adjustl(itext)), hdferr)
             call create_hdf_group(file, trim(itext))
          end if

          ! Collect beam contributions from each core
          call mpi_reduce(self%src(k)%T(i)%np, n, 1, MPI_INTEGER, MPI_SUM, 0, comm_pre, ierr)
          if (myid_pre == 0) then
             allocate(ind(n), beam(n,self%nmaps))
             n = 0
             m = self%src(k)%T(i)%np
             ind(n+1:n+m)    = self%src(k)%T(i)%pix(:,2)
             beam(n+1:n+m,:) = self%src(k)%T(i)%map
             n               = n+m
             do j = 1, numprocs_pre-1
                call mpi_recv(m, 1, MPI_INTEGER, j, 61, comm_pre, status, ierr)
                if (m > 0) then
                   call mpi_recv(ind(n+1:n+m), m, MPI_DOUBLE_PRECISION, j, &
                        & 61, comm_pre, status, ierr)
                   call mpi_recv(beam(n+1:n+m,:), m*nmaps, MPI_DOUBLE_PRECISION, j, &
                        & 61, comm_pre, status, ierr)
                end if
                n = n+m
             end do
             ! Sort according to increasing pixel number
             do j = 2, n
                itmp          = ind(j)
                rtmp(1:nmaps) = beam(j,1:nmaps)
                l             = j-1
                do while (l > 0)
                   if (ind(l) <= itmp) exit
                   ind(l+1)     = ind(l)
                   beam(l+1,:)  = beam(l,:)
                   l            = l-1
                end do
                ind(l+1)    = itmp
                beam(l+1,:) = rtmp(1:nmaps)
             end do

             ! Write to HDF file
             call write_hdf(file, trim(adjustl(itext))//'/indices', ind)
             call write_hdf(file, trim(adjustl(itext))//'/values',  beam)
             deallocate(ind, beam)
          else
             m = self%src(k)%T(i)%np
             call mpi_send(m, 1, MPI_INTEGER, 0, 61, comm_pre, ierr)
             if (m > 0) then
                call mpi_send(self%src(k)%T(i)%pix(:,2), m, MPI_INTEGER, 0, 61, comm_pre, ierr)
                call mpi_send(self%src(k)%T(i)%map, m*nmaps, MPI_DOUBLE_PRECISION, 0, 61, comm_pre, ierr)
             end if
          end if
       end do
    end do
    if (myid_pre == 0) call close_hdf_file(file)    
    
  end subroutine dump_beams_to_hdf
  

  subroutine compute_symmetric_beam(band, glon, glat, T, bl, beamfile)
    implicit none
    integer(i4b), intent(in)     :: band
    real(dp),     intent(in)     :: glon, glat
    type(Tnu),    intent(inout)  :: T
    real(dp),  dimension(0:,1:), intent(in), optional :: bl
    character(len=*),            intent(in), optional :: beamfile

    integer(i4b) :: i, j, k(1), l, nside, n, npix, nlist, q, itmp, ierr
    integer(i4b), save :: band_cache = -1
    real(dp)     :: vec0(3), vec(3), tmax, theta, t1, t2, t3, t4, bmax, rtmp(3), b_max(3), b_tot(3)
    integer(i4b),      allocatable, dimension(:)       :: listpix
    integer(i4b),      allocatable, dimension(:,:)     :: mypix
    real(dp),          allocatable, dimension(:,:)     :: beam, mybeam
    type(spline_type), allocatable, dimension(:), save :: br

    !call wall_time(t1)
    
    ! Get azimuthally symmetric beam, either from Bl's or from file
    !call wall_time(t3)
    if (band /= band_cache) then
       if (allocated(br)) deallocate(br)
       if (present(bl)) then
          call compute_radial_beam(T%nmaps, bl, br)
       else if (present(beamfile)) then
          call read_radial_beam(T%nmaps, beamfile, br)
       end if
       band_cache = band
    end if
    !call wall_time(t4)
!    write(*,*) 'init = ', t4-t3

    ! Find maximum radius over all polarization modes
    !call wall_time(t3)
    tmax = 0.d0
    q    = 4            ! Nside ratio between highres and lowres maps
    do i = 1, T%nmaps
       tmax = max(tmax, maxval(br(i)%x))
    end do
    nside = q*T%nside                   ! Adopt a twice higher resolution to mimic pixwin
    npix  = 4*(tmax / (pi/3/nside))**2  ! Rough npix estimate for current beam
    call ang2vec(0.5d0*pi-glat, glon, vec0)
    allocate(listpix(0:npix-1), beam(0:npix-1,T%nmaps))
    call query_disc(nside, vec0, tmax, listpix, nlist)
    !call wall_time(t4)
!    write(*,*) 'query = ', t4-t3

    ! Make a high-resolution pixelized beam map centered on given position, and
    ! downgrade pixel number to correct Nside
    !call wall_time(t3)
    do i = 0, nlist-1
       call pix2vec_ring(nside, listpix(i), vec)
       call angdist(vec0, vec, theta)
       if (theta > tmax) then
          beam(i,j)  = 0.d0
          listpix(i) = 0.d0
       else
          do j = 1, T%nmaps
             beam(i,j) = splint(br(j), theta)
          end do
          call ring2nest(nside, listpix(i), listpix(i))
          listpix(i) = listpix(i)/q**2
          call nest2ring(T%nside, listpix(i), listpix(i))
       end if
    end do
    !call wall_time(t4)
!    write(*,*) 'build = ', t4-t3, ', nlist = ', nlist

    ! Sort listpix according to increasing pixel number; it's already almost sorted, so
    ! just do a simple insertion sort
    !call wall_time(t3)
    do i = 0, nlist-1
       itmp            = listpix(i)
       rtmp(1:T%nmaps) = beam(i,1:T%nmaps)
       j               = i-1
       do while (j >= 0)
          if (listpix(j) <= itmp) exit
          listpix(j+1) = listpix(j)
          beam(j+1,:)  = beam(j,:)
          j            = j-1
       end do
       listpix(j+1) = itmp
       beam(j+1,:)  = rtmp(1:T%nmaps)
    end do
    !call wall_time(t4)
!    write(*,*) 'sort = ', t4-t3

    ! Find number of pixels belonging to current processor
    !call wall_time(t3)
    allocate(mybeam(nlist,T%nmaps), mypix(nlist,2))
    T%np = 0
    i    = 0
    j    = locate(data(band)%info%pix, listpix(i))
    if (j > 0) then
       do while (.true.)
          if (listpix(i) == data(band)%info%pix(j)) then
             T%np            = T%np + 1
             mypix(T%np,1)   = j-1
             mypix(T%np,2)   = data(band)%info%pix(j)
             mybeam(T%np,:)  = beam(i,:)
             do while (i < nlist-1)
                i = i+1
                if (listpix(i-1) == listpix(i)) then
                   mybeam(T%np,:) = mybeam(T%np,:) + beam(i,:)
                else
                   exit
                end if
             end do
             j               = j+1
          else if (listpix(i) < data(band)%info%pix(j)) then
             i               = i+1
          else
             j               = j+1
          end if
          if (i > nlist-1) exit
          if (j > data(band)%info%np) exit
       end do
    end if

    ! Store pixels that belong to current processor    
    do i = 1, T%nmaps
       b_max(i) = maxval(mybeam(1:T%np,i))
       b_tot(i) = sum(mybeam(1:T%np,i))
    end do
    call mpi_allreduce(MPI_IN_PLACE, b_max(1:T%nmaps), T%nmaps, MPI_DOUBLE_PRECISION, &
         & MPI_MAX, comm_pre, ierr)
    call mpi_allreduce(MPI_IN_PLACE, b_tot(1:T%nmaps), T%nmaps, MPI_DOUBLE_PRECISION, &
         & MPI_SUM, comm_pre, ierr)

    allocate(T%pix(T%np,2), T%map(T%np,T%nmaps), T%Omega_b(T%nmaps))
    T%pix = mypix(1:T%np,:)
    do i = 1, T%nmaps
       T%map(:,i)   = mybeam(1:T%np,i) / b_max(i)
       T%Omega_b(i) = b_tot(i)/b_max(i) * 4.d0*pi/(12.d0*T%nside**2)
    end do

    deallocate(listpix, mypix, beam, mybeam)
    
  end subroutine compute_symmetric_beam

  subroutine initPtsrcPrecond(comm)
    implicit none
    integer(i4b),                intent(in) :: comm

    integer(i4b) :: i, i1, i2, j, j1, j2, k1, k2, q, l, m, n, p, p1, p2, n1, n2, myid, ierr, cnt
    real(dp)     :: t1, t2
    logical(lgt) :: skip
    class(comm_comp),         pointer :: c, c1, c2
    class(comm_ptsrc_comp),   pointer :: pt1, pt2
    real(dp),     allocatable, dimension(:,:) :: mat, mat2

    if (ncomp_pre == 0) return

    call mpi_comm_rank(comm, myid, ierr)
        
    ! Build frequency-dependent part of preconditioner
    call wall_time(t1)
    allocate(P_cr%invM_src(1,nmaps_pre))
    allocate(mat(npre,npre), mat2(npre,npre))
    do j = 1, nmaps_pre

       mat = 0.d0
       i1  = 0
       c1 => compList
       do while (associated(c1))
          skip = .true.
          select type (c1)
          class is (comm_ptsrc_comp)
             pt1  => c1
             skip = .false.
          end select
          if (skip .or. j > pt1%nmaps) then
             c1 => c1%next()
             cycle
          end if
          do k1 = 1, pt1%nsrc
             !write(*,*) k1, pt1%nsrc             
             i1 = i1+1

             i2 = 0
             c2 => compList
             do while (associated(c2))
                !do j2 = 1, ncomp_pre
                skip = .true.
                select type (c2)
                class is (comm_ptsrc_comp)
                   pt2 => c2
                   skip = .false.
                end select
                if (skip .or. j > pt2%nmaps) then
                   c2 => c2%next()
                   cycle
                end if
                do k2 = 1, pt2%nsrc
                   !write(*,*) k2, pt2%nsrc
                   i2 = i2+1
                   if (i2 < i1) cycle

                   do l = 1, numband
                      n1 = pt1%src(k1)%T(l)%np
                      n2 = pt2%src(k2)%T(l)%np

                      ! Search for common pixels; skip if no pixel overlap
                      if (n1 == 0 .or. n2 == 0) cycle
                      if (pt1%src(k1)%T(l)%pix(1,1)  > pt2%src(k2)%T(l)%pix(n2,1)) cycle
                      if (pt1%src(k1)%T(l)%pix(n1,1) < pt2%src(k2)%T(l)%pix(1,1))  cycle

                      p1 = 1
                      p2 = 1
                      do while (.true.)
                         if (pt1%src(k1)%T(l)%pix(p1,1) == pt2%src(k2)%T(l)%pix(p2,1)) then
                            p  = pt1%src(k1)%T(l)%pix(p1,1)
                            mat(i1,i2) = mat(i1,i2) + &
                                 & data(l)%N%invN_diag%map(p,j) * &          ! invN_{p,p}
                                 & pt1%src(k1)%T(l)%map(p1,j) * & ! B_1
                                 & pt2%src(k2)%T(l)%map(p2,j) * & ! B_2
                                 & pt1%src(k1)%T(l)%F(j)      * & ! F_1
                                 & pt2%src(k2)%T(l)%F(j)      * & ! F_2
                                 & pt1%getScale(l,k1,j)       * & ! Unit 1
                                 & pt2%getScale(l,k2,j)           ! Unit 2
                            p1 = p1+1
                            p2 = p2+1
                         else if (pt1%src(k1)%T(l)%pix(p1,1) < pt2%src(k2)%T(l)%pix(p2,1)) then
                            p1 = p1+1
                         else
                            p2 = p2+1
                         end if
                         if (p1 >= n1 .or. p2 >= n2) exit
                         if (pt1%src(k1)%T(l)%pix(p1,1) > pt2%src(k2)%T(l)%pix(n2,1)) exit
                         if (pt1%src(k1)%T(l)%pix(n1,1) < pt2%src(k2)%T(l)%pix(p2,1)) exit
                      end do
                   end do
                   mat(i2,i1) = mat(i1,i2)
                end do
                c2 => c2%next()
             end do
          end do
          c1 => c1%next()
       end do

       ! Collect contributions from all cores
       call mpi_reduce(mat, mat2, size(mat2), MPI_DOUBLE_PRECISION, MPI_SUM, 0, comm, ierr)
       if (myid == 0) then
          call invert_matrix_with_mask(mat2)
          allocate(P_cr%invM_src(1,j)%M(npre,npre))
          P_cr%invM_src(1,j)%M = mat2
       end if
    end do
    call wall_time(t2)
    if (myid_pre == 0) write(*,*) 'ptsrc precond init = ', real(t2-t1,sp)

    deallocate(mat,mat2)
    
  end subroutine initPtsrcPrecond

  subroutine updatePtsrcPrecond
    implicit none

    ! Placeholder for now; already fully initialized
    if (npre == 0) return
       
  end subroutine updatePtsrcPrecond


  subroutine applyPtsrcPrecond(x)
    implicit none
    real(dp),           dimension(:), intent(inout) :: x

    integer(i4b)              :: i, j, k, l, m, nmaps
    logical(lgt)              :: skip
    real(dp), allocatable, dimension(:,:) :: amp
    real(dp), allocatable, dimension(:,:) :: y
    class(comm_comp),       pointer :: c
    class(comm_ptsrc_comp), pointer :: pt

    if (npre == 0 .or. myid_pre /= 0) return
    
    ! Reformat linear array into y(npre,nalm,nmaps) structure
    allocate(y(npre,nmaps_pre))
    y = 0.d0
    l = 1
    c => compList
    do while (associated(c))
       skip = .true.
       select type (c)
       class is (comm_ptsrc_comp)
          pt => c
          skip = .false.
       end select
       if (skip) then
          c => c%next()
          cycle
       end if
       call cr_extract_comp(pt%id, x, amp)
       do k = 1, pt%nmaps
          y(l:l+pt%nsrc-1,k) = amp(:,k)
       end do
       l  = l + pt%nsrc
       c => c%next()
       deallocate(amp)
    end do

    ! Multiply with preconditioner
    do j = 1, nmaps_pre
       y(:,j) = matmul(P_cr%invM_src(1,j)%M, y(:,j))
    end do

    ! Reformat y(npre,nmaps) structure back into linear array
    l = 1
    c => compList
    do while (associated(c))
       skip = .true.
       select type (c)
       class is (comm_ptsrc_comp)
          pt => c
          skip = .false.
       end select
       if (skip) then
          c => c%next()
          cycle
       end if
       allocate(amp(pt%nsrc,pt%nmaps))
       do k = 1, pt%nmaps
          amp(:,k) = y(l:l+pt%nsrc-1,k)
       end do
       call cr_insert_comp(pt%id, .false., amp, x)
       l = l + pt%nsrc
       c => c%next()
       deallocate(amp)
    end do
        
    deallocate(y)

  end subroutine applyPtsrcPrecond

  function getScale(self, band, id, pol)
    implicit none
    class(comm_ptsrc_comp), intent(in) :: self
    integer(i4b),           intent(in) :: band, id, pol
    real(dp)                           :: getScale

    if (trim(self%type) == 'radio' .or. trim(self%type) == 'fir') then
       getScale = 1.d-23 * (c/self%nu_ref)**2 / (2.d0*k_b*self%src(id)%T(band)%Omega_b(pol))
    end if

  end function getScale

  subroutine read_radial_beam(nmaps, beamfile, br)
    implicit none
    integer(i4b),                                 intent(in)  :: nmaps
    character(len=*),                             intent(in)  :: beamfile
    type(spline_type), allocatable, dimension(:), intent(out) :: br

    integer(i4b) :: i, j, n, unit
    character(len=1024) :: line
    real(dp), allocatable, dimension(:)   :: x
    real(dp), allocatable, dimension(:,:) :: y

    ! Find number of entries
    unit = getlun()
    open(unit,file=trim(beamfile), recl=1024, status='old')
    n = 0
    do while (.true.)
       read(unit,'(a)',end=10) line
       line = trim(adjustl(line))
       if (line(1:1) == '#' .or. line(1:1) == ' ') cycle
       n = n+1
    end do
10  close(unit)

    allocate(x(n), y(n,nmaps))
    n = 0
    open(unit,file=trim(beamfile), recl=1024, status='old')
    do while (.true.)
       read(unit,'(a)',end=11) line
       line = trim(adjustl(line))
       if (line(1:1) == '#' .or. line(1:1) == ' ') cycle
       n = n+1
       read(line,*) x(n), y(n,:)
    end do
11  close(unit)

    ! Spline beam
    allocate(br(nmaps))
    do i = 1, nmaps
       x      = x * DEG2RAD
       y(:,i) = y(:,i) / maxval(y(:,i))
       call spline(br(i), x, y(:,i))
    end do

    deallocate(x, y)

  end subroutine read_radial_beam

  subroutine compute_radial_beam(nmaps, bl, br)
    implicit none
    integer(i4b),                                     intent(in)  :: nmaps
    real(dp),                       dimension(0:,1:), intent(in)  :: bl
    type(spline_type), allocatable, dimension(:),     intent(out) :: br

    integer(i4b)  :: i, j, k, m, n, l, lmax
    real(dp)      :: theta_max, threshold
    real(dp), allocatable, dimension(:)   :: x, pl
    real(dp), allocatable, dimension(:,:) :: y
    
    n         = 1000
    lmax      = size(bl,1)-1
    threshold = 1.d-6

    ! Find typical size
    l    = 0
    do while (bl(l,1) > 0.5d0)
       l = l+1
    end do
    theta_max = pi/l * 10.d0
    
    ! Compute radial beams
    allocate(x(n), y(n,nmaps), pl(0:lmax))
    do i = 1, n
       x(i) = theta_max/(n-1) * real(i-1,dp)
       call comp_normalised_Plm(lmax, 0, x(i), pl)
       do j = 1, nmaps
          y(i,j) = 0.d0
          do l = 0, lmax
             y(i,j) = y(i,j) + bl(l,j)*pl(l)/sqrt(4.d0*pi/real(2*l+1,dp))
          end do
       end do
    end do

    ! Spline significant part of beam profile
    allocate(br(nmaps))
    do j = 1, nmaps
       y(:,j) = y(:,j) / maxval(y(:,j))
       m      = 0
       do while (y(m+1,j) > threshold .and. m < n)
          m = m+1
       end do
       call spline(br(j), x(1:m), y(1:m,j))
    end do

    deallocate(x, y, pl)
    
  end subroutine compute_radial_beam

  ! Sample spectral parameters
  subroutine samplePtsrcSpecInd(self, handle)
    implicit none
    class(comm_ptsrc_comp),                  intent(inout)        :: self
    type(planck_rng),                        intent(inout)        :: handle
  end subroutine samplePtsrcSpecInd
  
end module comm_ptsrc_comp_mod
