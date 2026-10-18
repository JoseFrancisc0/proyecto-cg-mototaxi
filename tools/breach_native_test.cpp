#include "drainage.h"
#include <cmath>
#include <iostream>
#include <vector>
int main(){
 const int n=65;std::vector<double> h(n*n);
 for(int z=0;z<n;z++)for(int x=0;x<n;x++){
  double r=std::hypot(x-32.0,z-32.0);
  h[z*n+x]=r<10?-2+r*.02:(r<15?7.0:std::max(0.0,6.0-(r-15)*.4));
 }
 auto original=h;DrainageField field;field.breach_multiscale(h,n,1,8);field.compute(h,n,1,25);
 int failures=0,sinks=0;double outgoing=0;
 for(int i=0;i<n*n;i++){
  if(!std::isfinite(h[i])||h[i]>original[i]+1e-10)failures++;
  bool boundary=i%n==0||i%n==n-1||i/n==0||i/n==n-1;
  int j=field.receiver[i];
  if(!boundary && (j<0||h[j]>=h[i]))sinks++;
  double sum=0;for(int d=0;d<8;d++)sum+=field.weights[i*8+d];
  if(!boundary&&std::abs(sum-1)>1e-10)failures++;
  if(boundary)outgoing+=field.accumulation[i];
 }
 if(sinks||std::abs(outgoing-n*n)>.001)failures++;
 auto duplicate=original;DrainageField repeated;repeated.breach_multiscale(duplicate,n,1,8);
 if(duplicate!=h)failures++;
 std::cout<<"Bowl breach: "<<failures<<" errors, "<<sinks<<" interior sinks; max cut "<<field.breach_max_depth<<", outlet area "<<outgoing<<"\n";
 return failures?1:0;
}
