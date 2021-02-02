! Copyright (C) 2014 Arne Luechow
! Copyright (C) 2015 Sebastian Klahm
!
! SPDX-License-Identifier: GPL-3.0-or-later


!  module for handling (Gaussian) cube data structures                                     
!  
!  The cube data structure is defined as a Fortran class
!  in addition to set/get this class allows "addData"
!  where for a (x,y,z,val) tupel the closest grid point is
!  located and val is added to the grid point value.
!  This is equivalent to a 3-dim binning operation.
!  Careful: the initial grid defines the bins, the coordinates
!  of the corresponding value are given by the *center* of the bin

MODULE gcube_m
    use kinds_m, only: r8
    use error_m
#ifdef MPI
    use MPI_F08
#endif

    implicit none

    type gcube
        real(r8), pointer  :: bins(:,:,:) => null()    ! actual bins
        real(r8)           :: ax=0,bx=0,ay=0,by=0,az=0,bz=0           ! lower/upper borders
        real(r8)           :: hx=0,hy=0,hz=0           ! step size
        integer          :: n=0                      ! # of bins per dimension
        character(len=80):: line1="cube file generated by gcube_m"
        character(len=80):: line2="outer loop x, middle y, inner z"
        integer          :: ncenter=0                ! molecule: # atoms
        real(r8), pointer  :: cx(:) => null()          ! x,y,z coords
        real(r8), pointer  :: cy(:) => null()
        real(r8), pointer  :: cz(:) => null()
        integer, pointer :: an(:) => null()          ! atom number
        integer          :: sbin=0
    contains
        procedure :: initBins => gcube_initBins
        procedure :: setMolecule => gcube_setMolecule
        procedure :: setLines => gcube_setLines
        procedure :: clear => gcube_clear
        procedure :: destroy => gcube_destroy
        procedure :: getnobins => gcube_getnobins
        procedure :: addData => gcube_addData
        procedure :: getData => gcube_getData
        procedure :: setData => gcube_setData
        procedure :: getBinCenter => gcube_getBinCenter
        procedure :: reduceAllNodes => gcube_reduceAllNodes
        procedure :: writeToFile => gcube_writeToFile
    end type gcube

contains

    subroutine gcube_initBins(this,n,ax,bx,ay,by,az,bz,s_bins)
        class(gcube), intent(inout) :: this
        integer, intent(in)        :: n
        real(r8), intent(in)         :: ax,bx,ay,by,az,bz
        integer alstat
        integer, intent(in), optional          :: s_bins
   
        this%n = n
        if (associated(this%bins)) deallocate(this%bins)
        allocate(this%bins(0:n-1,0:n-1,0:n-1),stat=alstat)
        if (alstat/=0) call abortp("gcube_initBins: allocation failed")
        this%ax = ax; this%bx = bx
        this%ay = ay; this%by = by
        this%az = az; this%bz = bz
        this%hx = (bx-ax)/this%n
        this%hy = (by-ay)/this%n
        this%hz = (bz-az)/this%n
        this%bins = 0.d0
        if (present(s_bins)) this%sbin = s_bins
    end subroutine gcube_initBins


    subroutine gcube_setMolecule(this,x,y,z,an)
        class(gcube), intent(inout) :: this
        real(r8),intent(in)          :: x(:),y(:),z(:)
        integer,intent(in)         :: an(:)
        integer n

        call assert(size(x)>0 .and. size(x)==size(y) .and. size(x)==size(z) .and. size(x)==size(an), &
            "gcube_setMolecule: illegal sizes")
        if (associated(this%cx)) then
            deallocate(this%cx,this%cy,this%cz,this%an)
        end if
        n = size(x)
        this%ncenter = n
        allocate(this%cx(n),this%cy(n),this%cz(n),this%an(n))
        this%cx = x
        this%cy = y
        this%cz = z
        this%an = an
    end subroutine gcube_setMolecule


    subroutine gcube_setLines(this,line1,line2)
        class(gcube), intent(inout) :: this
        character(len=80), intent(in) :: line1,line2
        this%line1 = line1        
        this%line2 = line2
    end subroutine gcube_setLines


    subroutine gcube_clear(this)
        class(gcube), intent(inout) :: this
        this%bins = 0.d0
    end subroutine gcube_clear


    subroutine gcube_destroy(this)
        class(gcube), intent(inout) :: this
        if (associated(this%cx)) deallocate(this%cx,this%cy,this%cz,this%an)
        if (associated(this%bins)) deallocate(this%bins)
    end subroutine gcube_destroy


    integer function gcube_getnobins(this)
        class(gcube), intent(inout) :: this
        gcube_getnobins = this%n
    end function gcube_getnobins


    subroutine gcube_addData(this,x,y,z,value)
        class(gcube), intent(inout) :: this
        real(r8) , intent(in)         :: x,y,z,value
        integer kx,ky,kz    

        kx = max(0,int((x - this%ax)/this%hx))
        kx = min(kx,this%n-1)
        ky = max(0,int((y - this%ay)/this%hy))
        ky = min(ky,this%n-1)
        kz = max(0,int((z - this%az)/this%hz))
        kz = min(kz,this%n-1)
        if (kx>=0 .and. kx<=this%n-1 .and. ky>=0 .and. ky<=this%n-1 .and. kz>=0 .and. kz<=this%n-1) then
           this%bins(kx,ky,kz) = this%bins(kx,ky,kz) + value
        end if
    end subroutine gcube_addData


    real(r8) function gcube_getData(this,ix,iy,iz)
        class(gcube), intent(inout) :: this
        integer, intent(in)        :: ix,iy,iz
        integer n

        n = this%n - 1
        if (ix<0.or.ix>n.or.iy<0.or.iy>n.or.iz<0.or.iz>n) then
            call abortp('gcube_getData: index over/underflow error')
        end if
        gcube_getData = this%bins(ix,iy,iz)
    end function gcube_getData


    subroutine gcube_setData(this,ix,iy,iz,val)
        class(gcube), intent(inout) :: this
        integer, intent(in)        :: ix,iy,iz
        real(r8), intent(in)         :: val
        integer n

        n = this%n - 1
        if (ix<0.or.ix>n.or.iy<0.or.iy>n.or.iz<0.or.iz>n) then
            call abortp(' gcube_getData: overflow error')
        end if
        this%bins(ix,iy,iz) = val
    end subroutine gcube_setData


    subroutine gcube_getBinCenter(this,kx,ky,kz,cx,cy,cz)
        ! returns *center* of the bin (ix,iy,iz)
        class(gcube), intent(inout) :: this
        real(r8), intent(out)      :: cx,cy,cz
        integer, intent(in)      :: kx,ky,kz
        cx = this%ax + (kx+0.5)*this%hx
        cy = this%ay + (ky+0.5)*this%hy
        cz = this%az + (kz+0.5)*this%hz
    end subroutine gcube_getBinCenter


    subroutine gcube_reduceAllNodes(this)
        class(gcube), intent(inout) :: this
        real(r8)                     :: sendbuf(this%n**3),recvbuf(this%n**3)
        integer            :: c,i,j,k

        c = 1
        do i =0,this%n-1
            do j=0,this%n-1
                do k=0,this%n-1
                    sendbuf(c) = this%bins(i,j,k)
                    c = c + 1
                enddo
            enddo
        enddo
        recvbuf = 0
#ifdef MPI
        call mpi_allreduce(sendbuf,recvbuf,this%n**3,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD)
#else
        recvbuf = sendbuf
#endif
        c = 1
        do i =0,this%n-1
            do j=0,this%n-1
                do k=0,this%n-1
                    this%bins(i,j,k) = recvbuf(c)
                    c = c + 1
                enddo
            enddo
        enddo
    end subroutine gcube_reduceAllNodes


    subroutine gcube_writeToFile(this,filename)
        class(gcube), intent(inout)    :: this
        character(len=80), intent(in) :: filename
        integer       :: i
        integer       :: i1,i2,i3
        integer, parameter :: iu=20

        if (this%sbin > 0) then
            call gcube_writeToTrimFile (this,filename)
        else

            open(iu,file=filename,status='unknown')  
            call assert(associated(this%cx),'gcube_writeToFile: atoms not set')
            call assert(associated(this%bins),'gcube_writeToFile: bins not allocated')

            write(iu,'(a)') this%line1
            write(iu,'(a)') this%line2
            write(iu,100) this%ncenter,this%ax+this%hx/2,this%ay+this%hy/2,this%az+this%hz/2
            write(iu,100) this%n,dble(this%hx),dble(0),dble(0)
            write(iu,100) this%n,dble(0),dble(this%hy),dble(0)
            write(iu,100) this%n,dble(0),dble(0),dble(this%hz)

            do i=1,this%ncenter
                write(iu,101) this%an(i),0.d0,this%cx(i),this%cy(i),this%cz(i)
            end do

            do i1=0,this%n-1
                do i2=0,this%n-1
                    write(iu,102) (this%bins(i1,i2,i3),i3=0,this%n-1)
                enddo
            enddo
            close(iu)
100         format((I5,3F12.6))
101         format(((I5,4F12.6)))
102         format((6E13.5))
        endif
    end subroutine gcube_writeToFile


    subroutine gcube_writeToTrimFile(this,filename)
        class(gcube), intent(in)    :: this
        character(len=80), intent(in) :: filename
        integer       :: i1,i2,i3,i4
        integer, dimension(3) :: ref
        integer, parameter :: iu=20
        real(r8),dimension(:),allocatable :: bins_small

        ref=-1

        open(iu,file=filename,status='unknown')  
        call assert(associated(this%cx),'gcube_writeToTrimFile: atoms not set')
        call assert(associated(this%bins),'gcube_writeToTrimFile: bins not allocated')

        write(iu,'(a)') this%line1
        write(iu,'(a)') this%line2
        call give_ref()
        allocate(bins_small(2*this%sbin+1))
        write(iu,100) this%ncenter,&
        this%ax+this%hx*(0.5+ref(1)-this%sbin),&
        this%ay+this%hy*(0.5+ref(2)-this%sbin),&
        this%az+this%hz*(0.5+ref(3)-this%sbin)
        write(iu,100) this%sbin*2+1,dble(this%hx),dble(0),dble(0)
        write(iu,100) this%sbin*2+1,dble(0),dble(this%hy),dble(0)
        write(iu,100) this%sbin*2+1,dble(0),dble(0),dble(this%hz)

        do i1=1,this%ncenter
            write(iu,101) this%an(i1),0.d0,this%cx(i1),this%cy(i1),this%cz(i1)
        end do

        do i1=ref(1)-this%sbin,ref(1)+this%sbin
            do i2=ref(2)-this%sbin,ref(2)+this%sbin
                i4=1
                do i3=ref(3)-this%sbin,ref(3)+this%sbin
                    if(i1<0 .or. i1>this%n-1 .or. &
                        i2<0 .or. i2>this%n-1 .or. &
                        i3<0 .or. i3>this%n-1) then
                        bins_small(i4)=0.0
                    else
                        bins_small(i4)=this%bins(i1,i2,i3)
                    end if
                    i4=i4+1
                enddo
                write(iu,102) (bins_small(i4),i4=1,2*this%sbin+1)
            enddo
        enddo
        deallocate(bins_small)
        close(iu)
100     format((I5,3F12.6))
101     format(((I5,4F12.6)))
102     format((6E13.5))

    contains

        subroutine give_ref()
        real(r8) :: Sum,Sumi,Sumj,Sumk
        integer :: i,j,k

        Sum=0.0
        Sumi=0.0
        Sumj=0.0
        Sumk=0.0

        do i=0,this%n-1
            do j=0,this%n-1
                do k=0,this%n-1
                    Sumi=Sumi+i*this%bins(i,j,k)
                    Sumj=Sumj+j*this%bins(i,j,k)
                    Sumk=Sumk+k*this%bins(i,j,k)
                    Sum=Sum+this%bins(i,j,k)
                end do
            end do
        end do

        if(Sum .eq. 0) Sum=1

        ref(1)=NINT(Sumi/Sum)
        ref(2)=NINT(Sumj/Sum)
        ref(3)=NINT(Sumk/Sum)
        end subroutine give_ref

    end subroutine gcube_writeToTrimFile
    

end module gcube_m


