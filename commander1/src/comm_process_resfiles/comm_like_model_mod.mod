  c'  ^   k820309    l          18.0        ¡Cl[                                                                                                          
       comm_like_model_mod.f90 COMM_LIKE_MODEL_MOD              CL_FID INC_SPEC L_PIVOT                                                     
                            @                              
                            @                              
                         @                                '                     #X    #Y    #Z    #W    #GSET 	   #EMPTY 
                 $                                                              $                                                             $                                                             $                                                             $                             	               
                 $                             
                                                                                                                                                                                                                                                                                                                                    %         @                                                           #         @                                                      #PARFILE    #PARNAME    #PAR_INT    #PAR_CHAR    #PAR_STRING    #PAR_SP    #PAR_DP    #PAR_LGT              
                                                    1           
                                                    1                                                                                                                                                                                           1                                                	                                                      
                                                                                                              
                
          )       -DTû!	@        3.141592653589793238462643383279502884197#         @                                                      #CLFILE    #CLS              
                                                    1                                                            
 U              &                   &                                                                                                                                             1                                                                                                  2                                                                                                  3                                                                                                  4                                                                                                   5                                            !                                                      6%         @                               "                    
       #HANDLE #             
                                 #                     #PLANCK_RNG    #         @                                  $                    #M %   #IERR &             
                               %                   
 W              & p                  & p                                                                                    &                                                        '     
                
          *       ¶oüxâ?        0.5772156649015328606065120900824024310422                                             (                                                         #         @                                  )                    #ALMS_REAL *   #ALMS_CMPLX +             
                                 *                   
 \             & p                  & p                                                                                   +                    ]              & p                  & p                   & p                                           #         @                                  ,                    #ALMS_CMPLX -   #ALMS_REAL .             
                                -                    ^             & p                  & p                   & p                                                                                     .                   
 _              & p                  & p                                                     @ @                              /                       @                                0                       @                                1                       @                                2                       @                                3                       @ @                              4                     @@                              5                                   &                                                      @ @                              6                       @                                7                       @ @                              8                       @ @                              9                       @                                :                       @                                ;                       @ @                              <     
       +         @                                =                                   &                                                            @                                >                   
                &                   &                                                    @ @                              ?                   
                &                   &                                                    @                                @                   
                &                                                    @ @                              A                   
                &                                                    @ @                              B                   
                &                   &                                           #         @                                   C                    #PARFILE D             
  @                             D                    1 #         @                                  E                    #P F   #S_HAT G             
  @                              F                   
 
             & p                                                    D @                              G                   
               & p                  & p                                          #         @                                  H                    #P I   #S_HAT J             
                                 I                   
              &                                                     D                                J                   
               &                   &                                           #         @                                  K                    #P L   #S_HAT M             
                                 L                   
              &                                                     D @                              M                   
               &                   &                                           #         @                                   N                    #RNG_HANDLE O   #P P   #L_PROP Q             
D @                               O                     #PLANCK_RNG              D                                P                   
               &                                                     D                                Q                   
               &                   &                                           #         @                                   R                    #P S   #SQRT_S T   #IERR U             
                                 S                   
              &                                                     D                                T                   
               &                   &                                                     D @                              U            #         @                                  V                    #EULER W   #R X             
                                 W                   
              & p                                                    D                                X                   
                & p                  & p                                          #         @                                   Y                    #FILENAME Z   #SCALE [   #SAMPLES \             
  @                             Z                    1           
                                 [     
                
 @                              \                   
 #             &                   &                                                  4      fn#fn )   Ô   (   b   uapp(COMM_LIKE_MODEL_MOD     ü   @   J   COMM_LIKE_UTILS    <  @   J   ALM_TOOLS    |  @   J   RNGMOD "   ¼         PLANCK_RNG+RNGMOD $   =  H   a   PLANCK_RNG%X+RNGMOD $     H   a   PLANCK_RNG%Y+RNGMOD $   Í  H   a   PLANCK_RNG%Z+RNGMOD $     H   a   PLANCK_RNG%W+RNGMOD '   ]  H   a   PLANCK_RNG%GSET+RNGMOD (   ¥  H   a   PLANCK_RNG%EMPTY+RNGMOD "   í  p       I4B+HEALPIX_TYPES !   ]  p       DP+HEALPIX_TYPES "   Í  p       LGT+HEALPIX_TYPES ,   =  P       COMM_GETLUN+COMM_LIKE_UTILS 3     ²       COMM_GET_PARAMETER+COMM_LIKE_UTILS ;   ?  L   a   COMM_GET_PARAMETER%PARFILE+COMM_LIKE_UTILS ;     L   a   COMM_GET_PARAMETER%PARNAME+COMM_LIKE_UTILS ;   ×  @   a   COMM_GET_PARAMETER%PAR_INT+COMM_LIKE_UTILS <     P   a   COMM_GET_PARAMETER%PAR_CHAR+COMM_LIKE_UTILS >   g  L   a   COMM_GET_PARAMETER%PAR_STRING+COMM_LIKE_UTILS :   ³  @   a   COMM_GET_PARAMETER%PAR_SP+COMM_LIKE_UTILS :   ó  @   a   COMM_GET_PARAMETER%PAR_DP+COMM_LIKE_UTILS ;   3  @   a   COMM_GET_PARAMETER%PAR_LGT+COMM_LIKE_UTILS !   s         PI+HEALPIX_TYPES 7   	  ]       READ_FIDUCIAL_SPECTRUM+COMM_LIKE_UTILS >   i	  L   a   READ_FIDUCIAL_SPECTRUM%CLFILE+COMM_LIKE_UTILS ;   µ	  ¤   a   READ_FIDUCIAL_SPECTRUM%CLS+COMM_LIKE_UTILS #   Y
  q       TT+COMM_LIKE_UTILS #   Ê
  q       TE+COMM_LIKE_UTILS #   ;  q       TB+COMM_LIKE_UTILS #   ¬  q       EE+COMM_LIKE_UTILS #     q       EB+COMM_LIKE_UTILS #     q       BB+COMM_LIKE_UTILS     ÿ  \       RAND_UNI+RNGMOD '   [  X   a   RAND_UNI%HANDLE+RNGMOD @   ³  Y       CHOLESKY_DECOMPOSE_WITH_MASK_DP+COMM_LIKE_UTILS B     ¬   a   CHOLESKY_DECOMPOSE_WITH_MASK_DP%M+COMM_LIKE_UTILS E   ¸  @   a   CHOLESKY_DECOMPOSE_WITH_MASK_DP%IERR+COMM_LIKE_UTILS $   ø         EULER+HEALPIX_TYPES "     p       DPC+HEALPIX_TYPES @     g       CONVERT_REAL_TO_COMPLEX_ALMS_DP+COMM_LIKE_UTILS J   i  ¬   a   CONVERT_REAL_TO_COMPLEX_ALMS_DP%ALMS_REAL+COMM_LIKE_UTILS K     È   a   CONVERT_REAL_TO_COMPLEX_ALMS_DP%ALMS_CMPLX+COMM_LIKE_UTILS =   Ý  g       CONVERT_COMPLEX_TO_REAL_ALMS+COMM_LIKE_UTILS H   D  È   a   CONVERT_COMPLEX_TO_REAL_ALMS%ALMS_CMPLX+COMM_LIKE_UTILS G     ¬   a   CONVERT_COMPLEX_TO_REAL_ALMS%ALMS_REAL+COMM_LIKE_UTILS    ¸  @       LMAX    ø  @       NSPEC    8  @       N_H    x  @       NMAPS    ¸  @       NUMCOMP    ø  @       VERBOSITY    8         INDMAP    Ä  @       MODEL      @       NPAR    D  @       LMIN_FIT      @       LMAX_FIT    Ä  @       IND_MIN      @       IND_MAX     D  @       DIR_PROP_RADIUS             PAR_LABEL      ¤       PRIOR_UNI    ¼  ¤       PRIOR_GAUSS    `         PAR_MODULO    ì         PAR_RMS    x  ¤       L_PROP_IN %     U       INITIALIZE_MODEL_MOD -   q  L   a   INITIALIZE_MODEL_MOD%PARFILE    ½  Z       COMPUTE_S_HAT          a   COMPUTE_S_HAT%P $   §  ¬   a   COMPUTE_S_HAT%S_HAT !   S  Z       COMPUTE_S_HAT_QN #   ­     a   COMPUTE_S_HAT_QN%P '   9  ¤   a   COMPUTE_S_HAT_QN%S_HAT .   Ý  Z       COMPUTE_S_HAT_POWER_ASYMMETRY 0   7     a   COMPUTE_S_HAT_POWER_ASYMMETRY%P 4   Ã  ¤   a   COMPUTE_S_HAT_POWER_ASYMMETRY%S_HAT ,   g   k       INITIALIZE_MODEL_PARAMETERS 7   Ò   X   a   INITIALIZE_MODEL_PARAMETERS%RNG_HANDLE .   *!     a   INITIALIZE_MODEL_PARAMETERS%P 3   ¶!  ¤   a   INITIALIZE_MODEL_PARAMETERS%L_PROP    Z"  e       GET_SQRT_S    ¿"     a   GET_SQRT_S%P "   K#  ¤   a   GET_SQRT_S%SQRT_S     ï#  @   a   GET_SQRT_S%IERR (   /$  Z       COMPUTE_ROTATION_MATRIX .   $     a   COMPUTE_ROTATION_MATRIX%EULER *   %  ¬   a   COMPUTE_ROTATION_MATRIX%R #   Å%  n       OUTPUT_PROP_MATRIX ,   3&  L   a   OUTPUT_PROP_MATRIX%FILENAME )   &  @   a   OUTPUT_PROP_MATRIX%SCALE +   ¿&  ¤   a   OUTPUT_PROP_MATRIX%SAMPLES 