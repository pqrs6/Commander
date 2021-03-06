module comm_tod_mapmaking_mod
  use comm_tod_mod
  use comm_utils
  use comm_shared_arr_mod
  use comm_map_mod
  implicit none


contains


  ! Compute map with white noise assumption from correlated noise 
  ! corrected and calibrated data, d' = (d-n_corr-n_temp)/gain 
  subroutine bin_TOD(tod, data, pix, psi, flag, A, b, scan, comp_S, b_mono)
    implicit none
    class(comm_tod),                             intent(in)    :: tod
    integer(i4b),                                intent(in)    :: scan
    real(sp),            dimension(1:,1:,1:),    intent(in)    :: data
    integer(i4b),        dimension(1:,1:),       intent(in)    :: pix, psi, flag
    real(dp),            dimension(1:,1:),       intent(inout) :: A
    real(dp),            dimension(1:,1:,1:),    intent(inout) :: b
    real(dp),            dimension(1:,1:,1:),    intent(inout), optional :: b_mono
    logical(lgt),                                intent(in)    :: comp_S

    integer(i4b) :: det, i, t, pix_, off, nout, psi_
    real(dp)     :: inv_sigmasq

    nout        = size(b,dim=1)

    do det = 1, tod%ndet
       if (.not. tod%scans(scan)%d(det)%accept) cycle
       !write(*,*) tod%scanid(scan), det, tod%scans(scan)%d(det)%sigma0
       off         = 6 + 4*(det-1)
       inv_sigmasq = (tod%scans(scan)%d(det)%gain/tod%scans(scan)%d(det)%sigma0)**2
       do t = 1, tod%scans(scan)%ntod
          
          if (iand(flag(t,det),tod%flag0) .ne. 0) cycle
          
          pix_    = tod%pix2ind(pix(t,det))
          psi_    = psi(t,det)
          
          A(1,pix_) = A(1,pix_) + 1.d0                                  * inv_sigmasq
          A(2,pix_) = A(2,pix_) + tod%cos2psi(psi_)                    * inv_sigmasq
          A(3,pix_) = A(3,pix_) + tod%cos2psi(psi_)**2                 * inv_sigmasq
          A(4,pix_) = A(4,pix_) + tod%sin2psi(psi_)                    * inv_sigmasq
          A(5,pix_) = A(5,pix_) + tod%cos2psi(psi_)*tod%sin2psi(psi_) * inv_sigmasq
          A(6,pix_) = A(6,pix_) + tod%sin2psi(psi_)**2                 * inv_sigmasq
          
          do i = 1, nout
             b(i,1,pix_) = b(i,1,pix_) + data(i,t,det)                      * inv_sigmasq
             b(i,2,pix_) = b(i,2,pix_) + data(i,t,det) * tod%cos2psi(psi_) * inv_sigmasq
             b(i,3,pix_) = b(i,3,pix_) + data(i,t,det) * tod%sin2psi(psi_) * inv_sigmasq
          end do
          
          if (present(b_mono)) then
             b_mono(1,pix_,det) = b_mono(1,pix_,det) +                      inv_sigmasq
             b_mono(2,pix_,det) = b_mono(2,pix_,det) + tod%cos2psi(psi_) * inv_sigmasq
             b_mono(3,pix_,det) = b_mono(3,pix_,det) + tod%sin2psi(psi_) * inv_sigmasq
          end if
          
          if (comp_S .and. det < tod%ndet) then
             A(off+1,pix_) = A(off+1,pix_) + 1.d0               * inv_sigmasq 
             A(off+2,pix_) = A(off+2,pix_) + tod%cos2psi(psi_) * inv_sigmasq
             A(off+3,pix_) = A(off+3,pix_) + tod%sin2psi(psi_) * inv_sigmasq
             A(off+4,pix_) = A(off+4,pix_) + 1.d0               * inv_sigmasq
             do i = 1, nout
                b(i,det+3,pix_) = b(i,det+3,pix_) + data(i,t,det) * inv_sigmasq 
             end do
          end if
          
       end do
    end do

  end subroutine bin_TOD

  subroutine finalize_binned_map(tod, handle, sA_map, sb_map, rms, outmaps, chisq_S, Sfile, mask, sb_mono, sys_mono, condmap)
    implicit none
    class(comm_tod),                      intent(in)    :: tod
    type(planck_rng),                     intent(inout) :: handle
    type(shared_2d_dp), intent(inout) :: sA_map
    type(shared_3d_dp), intent(inout) :: sb_map
    class(comm_map),                      intent(inout) :: rms
    class(map_ptr),  dimension(1:),       intent(inout), optional :: outmaps
    real(dp),        dimension(1:,1:),    intent(out),   optional :: chisq_S
    character(len=*),                     intent(in),    optional :: Sfile
    integer(i4b),    dimension(0:),       intent(in),    optional :: mask
    type(shared_3d_dp), intent(inout), optional :: sb_mono
    real(dp),        dimension(1:,1:,0:), intent(out),   optional :: sys_mono
    class(comm_map),                      intent(inout), optional :: condmap

    integer(i4b) :: i, j, k, nmaps, ierr, ndet, ncol, n_A, off, ndelta
    integer(i4b) :: det, nout, np0, comm, myid, nprocs
    real(dp), allocatable, dimension(:,:)   :: A_inv, As_inv, buff_2d
    real(dp), allocatable, dimension(:,:,:) :: b_tot, bs_tot, buff_3d
    real(dp), allocatable, dimension(:)     :: W, eta
    real(dp), allocatable, dimension(:,:)   :: A_tot
    class(comm_mapinfo), pointer :: info 
    class(comm_map), pointer :: smap 

    myid  = tod%myid
    nprocs= tod%numprocs
    comm  = tod%comm
    np0   = tod%info%np
    nout  = size(sb_map%a,dim=1)
    nmaps = tod%info%nmaps
    ndet  = tod%ndet
    n_A   = size(sA_map%a,dim=1)
    ncol  = size(sb_map%a,dim=2)
    ndelta = 0; if (present(chisq_S)) ndelta = size(chisq_S,dim=2)

    ! Collect contributions from all nodes
    !call update_status(status, "tod_final1")
    call mpi_win_fence(0, sA_map%win, ierr)
    if (sA_map%myid_shared == 0) then
       !allocate(buff_2d(size(sA_map%a,1),size(sA_map%a,2)))
!       call mpi_allreduce(sA_map%a, buff_2d, size(sA_map%a), &
!            & MPI_DOUBLE_PRECISION, MPI_SUM, sA_map%comm_inter, ierr)
       do i = 1, size(sA_map%a,1)
          call mpi_allreduce(MPI_IN_PLACE, sA_map%a(i,:), size(sA_map%a,2), &
               & MPI_DOUBLE_PRECISION, MPI_SUM, sA_map%comm_inter, ierr)
       end do
       !sA_map%a = buff_2d
       !deallocate(buff_2d)
    end if
    call mpi_win_fence(0, sA_map%win, ierr)
    call mpi_win_fence(0, sb_map%win, ierr)
    if (sb_map%myid_shared == 0) then
       !allocate(buff_3d(size(sb_map%a,1),size(sb_map%a,2),size(sb_map%a,3)))
       !call mpi_allreduce(sb_map%a, buff_3d, size(sb_map%a), &
       !     & MPI_DOUBLE_PRECISION, MPI_SUM, sb_map%comm_inter, ierr)
       do i = 1, size(sb_map%a,1)
          call mpi_allreduce(mpi_in_place, sb_map%a(i,:,:), size(sb_map%a(1,:,:)), &
               & MPI_DOUBLE_PRECISION, MPI_SUM, sb_map%comm_inter, ierr)
       end do
       !sb_map%a = buff_3d
       !deallocate(buff_3d)
    end if
    call mpi_win_fence(0, sb_map%win, ierr)
    if (present(sb_mono)) then
       call mpi_win_fence(0, sb_mono%win, ierr)
       if (sb_mono%myid_shared == 0) then
          call mpi_allreduce(MPI_IN_PLACE, sb_mono%a, size(sb_mono%a), &
               & MPI_DOUBLE_PRECISION, MPI_SUM, sb_mono%comm_inter, ierr)
       end if
       call mpi_win_fence(0, sb_mono%win, ierr)
    end if

    allocate(A_tot(n_A,0:np0-1), b_tot(nout,nmaps,0:np0-1), bs_tot(nout,ncol,0:np0-1), W(nmaps), eta(nmaps))
    A_tot  = sA_map%a(:,tod%info%pix+1)
    b_tot  = sb_map%a(:,1:nmaps,tod%info%pix+1)
    bs_tot = sb_map%a(:,:,tod%info%pix+1)
    if (present(sb_mono)) then
       do j = 1, ndet
          sys_mono(:,nmaps+j,:) = sb_mono%a(:,tod%info%pix+1,j)
       end do
    end if
    !call update_status(status, "tod_final2")

    ! Solve for local map and rms
    if (present(Sfile)) then
       info => comm_mapinfo(tod%comm, tod%info%nside, 0, ndet-1, .false.)
       smap => comm_map(info)
       smap%map = 0.d0
    end if
    allocate(A_inv(nmaps,nmaps), As_inv(ncol,ncol))
    !if (present(chisq_S)) smap%map = 0.d0
    if (present(chisq_S)) chisq_S = 0.d0
    do i = 0, np0-1
       if (all(b_tot(1,:,i) == 0.d0)) then
          !write(*,*) 'missing pixel',i, tod%myid
          if (present(sb_mono)) sys_mono(1:nmaps,1:nmaps,i) = 0.d0
          if (.not. present(chisq_S)) then
             rms%map(i,:) = 0.d0
             if (present(outmaps)) then
                do k = 1, nout
                   outmaps(k)%p%map(i,:) = 0.d0
                end do
             end if
          end if
          cycle
       end if

       A_inv      = 0.d0
       A_inv(1,1) = A_tot(1,i)
       A_inv(2,1) = A_tot(2,i)
       A_inv(1,2) = A_inv(2,1)
       A_inv(2,2) = A_tot(3,i)
       A_inv(3,1) = A_tot(4,i)
       A_inv(1,3) = A_inv(3,1)
       A_inv(3,2) = A_tot(5,i)
       A_inv(2,3) = A_inv(3,2)
       A_inv(3,3) = A_tot(6,i)
       if (present(chisq_S)) then
          As_inv = 0.d0
          As_inv(1:nmaps,1:nmaps) = A_inv
          do det = 1, ndet-1
             off                 = 6 + 4*(det-1)
             As_inv(1,    3+det) = A_tot(off+1,i)
             As_inv(3+det,1    ) = As_inv(1,3+det)
             As_inv(2,    3+det) = A_tot(off+2,i)
             As_inv(3+det,2    ) = As_inv(2,3+det)
             As_inv(3,    3+det) = A_tot(off+3,i)
             As_inv(3+det,3    ) = As_inv(3,3+det)
             As_inv(3+det,3+det) = A_tot(off+4,i)
          end do
       end if

       if (present(condmap)) then
          call get_eigenvalues(A_inv(1:nmaps,1:nmaps),W)
          if (minval(W) < 0.d0) then
!             if (maxval(W) == 0.d0 .or. minval(W) == 0.d0) then
                write(*,*) 'A_inv: ', A_inv
                write(*,*) 'W', W
!             end if
          end if
          if (minval(W) > 0) then
             condmap%map(i,1) = log10(max(abs(maxval(W)/minval(W)),1.d0))
          else
             condmap%map(i,1) = 30.d0
          end if
       end if
       
       call invert_singular_matrix(A_inv, 1d-12)
       do k = 1, tod%output_n_maps
          b_tot(k,1:nmaps,i) = matmul(A_inv,b_tot(k,1:nmaps,i))
       end do
!!$       if (tod%info%pix(i) == 100) then
!!$          write(*,*) 'b', b_tot(:,:,i)
!!$       end if 
       if (present(chisq_S)) then
          call invert_singular_matrix(As_inv, 1d-12)
          bs_tot(1,1:ncol,i) = matmul(As_inv,bs_tot(1,1:ncol,i))
          do k = tod%output_n_maps+1, nout
             bs_tot(k,1:ncol,i) = matmul(As_inv,bs_tot(k,1:ncol,i))
          end do
       end if

       if (present(sb_mono)) sys_mono(1:nmaps,1:nmaps,i) = A_inv(1:nmaps,1:nmaps)
       if (present(chisq_S)) then
          do j = 1, ndet-1
             if (mask(tod%info%pix(i+1)) == 0)  cycle
             if (As_inv(nmaps+j,nmaps+j) <= 0.d0) cycle
             chisq_S(j,1) = chisq_S(j,1) + bs_tot(1,nmaps+j,i)**2 / As_inv(nmaps+j,nmaps+j)
             do k = 2, ndelta
                chisq_S(j,k) = chisq_S(j,k) + bs_tot(tod%output_n_maps+k-1,nmaps+j,i)**2 / As_inv(nmaps+j,nmaps+j)
             end do
             if (present(Sfile) .and. As_inv(nmaps+j,nmaps+j) > 0.d0) then
                smap%map(i,j) = bs_tot(1,nmaps+j,i) / sqrt(As_inv(nmaps+j,nmaps+j))
             end if
          end do
       end if
       do j = 1, nmaps
          rms%map(i,j) = sqrt(A_inv(j,j))  * 1.d6 ! uK
          if (present(outmaps)) then
             do k = 1, tod%output_n_maps
                outmaps(k)%p%map(i,j) = b_tot(k,j,i) * 1.d6 ! uK
             end do
          end if
       end do
    end do

    if (present(chisq_S)) then
       if (myid == 0) then
          call mpi_reduce(mpi_in_place, chisq_S, size(chisq_S), &
               & MPI_DOUBLE_PRECISION, MPI_SUM, 0, comm, ierr)
       else
          call mpi_reduce(chisq_S,      chisq_S, size(chisq_S), &
               & MPI_DOUBLE_PRECISION, MPI_SUM, 0, comm, ierr)
       end if
       if (present(Sfile)) call smap%writeFITS(trim(Sfile))
    end if

    if (present(Sfile)) call smap%dealloc

    deallocate(A_inv,As_inv,A_tot,b_tot,bs_tot, W, eta)

  end subroutine finalize_binned_map


  subroutine sample_mono(tod, handle, sys_mono, res, rms, mask)
    implicit none
    class(comm_tod),                       intent(inout) :: tod
    type(planck_rng),                      intent(inout) :: handle
    real(dp),         dimension(1:,1:,0:), intent(in)    :: sys_mono
    class(comm_map),                       intent(in)    :: res, rms, mask

    integer(i4b) :: i, j, k, nstep, nmaps, ndet, ierr
    real(dp)     :: t1, t2, s(3), b(3), alpha, sigma, chisq, chisq0, chisq_prop, naccept
    logical(lgt) :: accept, first_call
    real(dp), allocatable, dimension(:)   :: mono0, mono_prop, mu, eta
    real(dp), allocatable, dimension(:,:) :: samples

    call wall_time(t1)

    first_call = .not. allocated(tod%L_prop_mono)
    sigma = 0.03d-6 ! RMS proposal in K
    alpha = 1.2d0   ! Covariance matrix scaling factor
    nmaps = size(sys_mono, dim=1)
    ndet  = size(sys_mono, dim=2)-nmaps
    allocate(mono0(ndet), mono_prop(ndet), eta(ndet), mu(ndet))
 
    ! Initialize monopoles on existing values
    if (tod%myid == 0) then
       do j = 1, ndet
          mono0(j) = tod%mono(j)
       end do

       if (first_call) then
          allocate(tod%L_prop_mono(ndet,ndet))
          tod%L_prop_mono = 0.d0
          do i = 1, ndet
             tod%L_prop_mono(i,i) = sigma
          end do
          nstep = 100000
          allocate(samples(ndet,nstep))
       else
          nstep = 1000
       end if
    end if
    call mpi_bcast(mono0, ndet,  MPI_DOUBLE_PRECISION, 0, res%info%comm, ierr)
    call mpi_bcast(nstep,    1,  MPI_INTEGER,          0, res%info%comm, ierr)

    ! Compute chisquare for old values; only include Q and U in evaluation; 
    ! add old correction to output map
    chisq = 0.d0
    do k = 0, res%info%np-1
       b = 0.d0
       do j = 1, ndet
          b = b + mono0(j) * sys_mono(:,nmaps+j,k)
       end do
       s = matmul(sys_mono(1:3,1:3,k),b) * 1.d6 ! uK
       if (mask%map(k,1) == 1.d0) then
          chisq = chisq + sum((res%map(k,2:3)-s(2:3))**2 / rms%map(k,2:3)**2)
       end if
    end do
    call mpi_reduce(chisq, chisq0, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, res%info%comm, ierr)

    naccept = 0
    if (res%info%myid == 0) open(78,file='mono.dat', recl=1024)
    do i = 1, nstep

       ! Propose new monopoles; force zero average
       if (res%info%myid == 0) then
          do j = 1, ndet
             eta(j) = rand_gauss(handle)
          end do
          mono_prop = mono0     + matmul(tod%L_prop_mono, eta)
          mono_prop = mono_prop - mean(mono_prop)
       end if
       call mpi_bcast(mono_prop, ndet,  MPI_DOUBLE_PRECISION, 0, res%info%comm, ierr)

       ! Compute chisquare for new values; only include Q and U in evaluation
       chisq = 0.d0
       do k = 0, res%info%np-1
          b = 0.d0
          do j = 1, ndet
             b = b + mono_prop(j) * sys_mono(:,nmaps+j,k)
          end do
          s = matmul(sys_mono(1:3,1:3,k),b) * 1.d6 ! uK
          if (mask%map(k,1) == 1) then
             chisq = chisq + sum((res%map(k,2:3)-s(2:3))**2 / rms%map(k,2:3)**2)
          end if
       end do
       call mpi_reduce(chisq, chisq_prop, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, res%info%comm, ierr)

       ! Apply Metropolis rule or maximize
       if (res%info%myid == 0) then
          if (trim(tod%operation) == 'optimize') then
             accept = chisq_prop <= chisq0
          else
             accept = (rand_uni(handle) < exp(-0.5d0 * (chisq_prop-chisq0)))
          end if
!!$          write(*,*) 'Mono chisq0 = ', chisq0, ', delta = ', chisq_prop-chisq0
!!$          write(*,*) 'm0 = ', real(mono0,sp)
!!$          write(*,*) 'm1 = ', real(mono_prop,sp)
       end if
       call mpi_bcast(accept, 1,  MPI_LOGICAL, 0, res%info%comm, ierr)

       if (accept) then
          mono0  = mono_prop
          chisq0 = chisq_prop
          naccept = naccept + 1
       end if
       if (res%info%myid == 0 .and. mod(i,100) == 0) write(78,*) i, chisq0, mono0
       if (first_call) samples(:,i) = mono0

    end do
    if (res%info%myid == 0) close(78)

    if (first_call .and. res%info%myid == 0) then
       do i = 1, ndet
          mu(i) = mean(samples(i,:))
          do j = 1, i
             tod%L_prop_mono(i,j) = mean((samples(i,:)-mu(i))*(samples(j,:)-mu(j)))
          end do
!          write(*,*) real(tod%L_prop_mono(i,:),sp) 
       end do
       call compute_hermitian_root(tod%L_prop_mono, 0.5d0)
       !call cholesky_decompose_single(tod%L_prop_mono)
       tod%L_prop_mono = alpha * tod%L_prop_mono
       deallocate(samples)
    end if


    ! Update parameters
    tod%mono = mono0

    call wall_time(t2)
    if (res%info%myid == 0) then
       write(*,fmt='(a,f8.3,a,f8.3)') 'Time for monopole sampling = ', t2-t1, ', accept = ', naccept/nstep
    end if

    deallocate(mono0, mono_prop, eta, mu)

  end subroutine sample_mono



end module comm_tod_mapmaking_mod
