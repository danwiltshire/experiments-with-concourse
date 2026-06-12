output "public_alb_dns_name" {
  description = "DNS name of the public-facing ALB."
  value       = aws_lb.concourse_public.dns_name
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB."
  value       = aws_lb.concourse_internal.dns_name
}

output "tsa_nlb_dns_name" {
  description = "DNS name of the internal NLB serving TSA (port 2222)."
  value       = aws_lb.tsa.dns_name
}

output "web_asg_name" {
  description = "Name of the web Auto Scaling Group."
  value       = aws_autoscaling_group.web.name
}

output "worker_asg_name" {
  description = "Name of the worker Auto Scaling Group."
  value       = aws_autoscaling_group.worker.name
}

output "web_security_group_id" {
  description = "Security group ID attached to web instances."
  value       = aws_security_group.web.id
}

output "worker_security_group_id" {
  description = "Security group ID attached to worker instances."
  value       = aws_security_group.worker.id
}
