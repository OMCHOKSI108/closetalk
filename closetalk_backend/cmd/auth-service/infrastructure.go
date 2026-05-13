package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	cwtypes "github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
	"github.com/aws/aws-sdk-go-v2/service/costexplorer"
	cetypes "github.com/aws/aws-sdk-go-v2/service/costexplorer/types"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	rdstypes "github.com/aws/aws-sdk-go-v2/service/rds/types"

	"github.com/redis/go-redis/v9"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

var (
	infraOnce   sync.Once
	infraCfg    aws.Config
	infraCfgErr error
)

func getInfraConfig() (aws.Config, error) {
	infraOnce.Do(func() {
		infraCfg, infraCfgErr = config.LoadDefaultConfig(context.Background())
	})
	return infraCfg, infraCfgErr
}

var (
	cwOnce   sync.Once
	cwClient *cloudwatch.Client
)

func getCWClient() *cloudwatch.Client {
	cwOnce.Do(func() {
		if cfg, err := getInfraConfig(); err == nil {
			cwClient = cloudwatch.NewFromConfig(cfg)
		}
	})
	return cwClient
}

var (
	ecsOnce   sync.Once
	ecsClient *ecs.Client
)

func getECSClient() *ecs.Client {
	ecsOnce.Do(func() {
		if cfg, err := getInfraConfig(); err == nil {
			ecsClient = ecs.NewFromConfig(cfg)
		}
	})
	return ecsClient
}

var (
	rdsOnce   sync.Once
	rdsClient *rds.Client
)

func getRDSClient() *rds.Client {
	rdsOnce.Do(func() {
		if cfg, err := getInfraConfig(); err == nil {
			rdsClient = rds.NewFromConfig(cfg)
		}
	})
	return rdsClient
}

var (
	ceOnce   sync.Once
	ceClient *costexplorer.Client
)

func getCEClient() *costexplorer.Client {
	ceOnce.Do(func() {
		if cfg, err := getInfraConfig(); err == nil {
			ceClient = costexplorer.NewFromConfig(cfg)
		}
	})
	return ceClient
}

type ResourceStatus struct {
	Name   string `json:"name"`
	Type   string `json:"type"`
	Status string `json:"status"`
	Detail string `json:"detail,omitempty"`
}

type InfraStatusResponse struct {
	Resources []ResourceStatus `json:"resources"`
	Overall   string           `json:"overall"`
}

func handleInfrastructureStatus(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	resources := []ResourceStatus{}
	clusterName := os.Getenv("ECS_CLUSTER")
	if clusterName == "" {
		clusterName = "closetalk-production"
	}

	ecsCli := getECSClient()
	if ecsCli != nil {
		for _, svcName := range []string{"auth-service", "message-service"} {
			out, err := ecsCli.DescribeServices(ctx, &ecs.DescribeServicesInput{
				Cluster:  aws.String(clusterName),
				Services: []string{svcName},
			})
			if err != nil {
				log.Printf("[infra] ecs describe %s: %v", svcName, err)
				resources = append(resources, ResourceStatus{Name: svcName, Type: "ecs", Status: "unknown", Detail: err.Error()})
				continue
			}
			if len(out.Services) == 0 {
				resources = append(resources, ResourceStatus{Name: svcName, Type: "ecs", Status: "unknown"})
				continue
			}
			s := out.Services[0]
			status := "unknown"
			if s.Status != nil {
				status = *s.Status
			}
			detail := fmt.Sprintf("running %d/%d, pending %d", s.RunningCount, s.DesiredCount, s.PendingCount)
			resources = append(resources, ResourceStatus{Name: svcName, Type: "ecs", Status: status, Detail: detail})
		}
	}

	rdsCli := getRDSClient()
	if rdsCli != nil {
		instances, err := rdsCli.DescribeDBInstances(ctx, &rds.DescribeDBInstancesInput{
			Filters: []rdstypes.Filter{{
				Name:   aws.String("db-instance-id"),
				Values: []string{"closetalk-production"},
			}},
		})
		if err != nil {
			log.Printf("[infra] rds describe: %v", err)
			fallbackOut, fallbackErr := rdsCli.DescribeDBInstances(ctx, &rds.DescribeDBInstancesInput{})
			if fallbackErr == nil {
				for _, db := range fallbackOut.DBInstances {
					if db.DBInstanceIdentifier != nil && strings.HasPrefix(*db.DBInstanceIdentifier, "closetalk") {
						status := "unknown"
						if db.DBInstanceStatus != nil {
							status = *db.DBInstanceStatus
						}
						detail := ""
						if db.DBInstanceClass != nil && db.AllocatedStorage != nil {
							detail = fmt.Sprintf("class=%s, storage=%dGB", *db.DBInstanceClass, *db.AllocatedStorage)
						}
						resources = append(resources, ResourceStatus{
							Name:   *db.DBInstanceIdentifier,
							Type:   "rds",
							Status: status,
							Detail: detail,
						})
						break
					}
				}
			}
		} else {
			for _, db := range instances.DBInstances {
				status := "unknown"
				if db.DBInstanceStatus != nil {
					status = *db.DBInstanceStatus
				}
				detail := ""
				if db.DBInstanceClass != nil && db.AllocatedStorage != nil {
					detail = fmt.Sprintf("class=%s, storage=%dGB", *db.DBInstanceClass, *db.AllocatedStorage)
				}
				resources = append(resources, ResourceStatus{
					Name:   *db.DBInstanceIdentifier,
					Type:   "rds",
					Status: status,
					Detail: detail,
				})
			}
		}
	}

	resources = append(resources, ResourceStatus{
		Name: "closetalk-media", Type: "s3", Status: "active",
		Detail: "bucket closetalk-media-706489758484",
	})
	resources = append(resources, ResourceStatus{
		Name: "closetalk-cf", Type: "cloudfront", Status: "active",
		Detail: "distribution E1IUMDB3PKS8YN",
	})

	runningCount := 0
	for _, res := range resources {
		lower := strings.ToLower(res.Status)
		if lower == "active" || lower == "running" || strings.Contains(lower, "running") {
			runningCount++
		}
	}

	overall := "healthy"
	if runningCount < len(resources) {
		overall = "degraded"
	}
	if runningCount == 0 {
		overall = "stopped"
	}

	writeJSON(w, http.StatusOK, InfraStatusResponse{
		Resources: resources,
		Overall:   overall,
	})
}

type MetricPoint struct {
	Timestamp int64   `json:"t"`
	Value     float64 `json:"v"`
}

type MetricSeries struct {
	Name   string        `json:"name"`
	Unit   string        `json:"unit"`
	Points []MetricPoint `json:"points"`
}

type MetricsResponse struct {
	ECS []MetricSeries `json:"ecs"`
	RDS []MetricSeries `json:"rds"`
	ALB []MetricSeries `json:"alb"`
}

func handleInfrastructureMetrics(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	now := time.Now()
	start := now.Add(-1 * time.Hour)
	period := int32(300)

	response := MetricsResponse{
		ECS: []MetricSeries{},
		RDS: []MetricSeries{},
		ALB: []MetricSeries{},
	}

	cw := getCWClient()
	if cw == nil {
		writeJSON(w, http.StatusOK, response)
		return
	}

	fetchMetrics := func(dimensionName, dimensionValue string, metricNames []string, namespace string) []MetricSeries {
		var series []MetricSeries
		for _, mn := range metricNames {
			out, err := cw.GetMetricStatistics(ctx, &cloudwatch.GetMetricStatisticsInput{
				Namespace:  aws.String(namespace),
				MetricName: aws.String(mn),
				StartTime:  aws.Time(start),
				EndTime:    aws.Time(now),
				Period:     aws.Int32(period),
				Statistics: []cwtypes.Statistic{cwtypes.StatisticAverage},
				Dimensions: []cwtypes.Dimension{{
					Name:  aws.String(dimensionName),
					Value: aws.String(dimensionValue),
				}},
			})
			if err != nil {
				log.Printf("[infra] cw get %s/%s: %v", namespace, mn, err)
				continue
			}
			points := []MetricPoint{}
			for _, dp := range out.Datapoints {
				if dp.Average != nil {
					points = append(points, MetricPoint{
						Timestamp: dp.Timestamp.UnixMilli(),
						Value:     math.Round(*dp.Average*100) / 100,
					})
				}
			}
			if len(points) > 0 {
				series = append(series, MetricSeries{
					Name:   mn,
					Unit:   string(out.Datapoints[0].Unit),
					Points: points,
				})
			}
		}
		return series
	}

	ecsMetrics := fetchMetrics("ClusterName", "closetalk-production", []string{"CPUUtilization", "MemoryUtilization"}, "AWS/ECS")
	if len(ecsMetrics) > 0 {
		response.ECS = ecsMetrics
	}

	rdsMetrics := fetchMetrics("DBInstanceIdentifier", "closetalk-production", []string{"CPUUtilization", "DatabaseConnections", "FreeStorageSpace"}, "AWS/RDS")
	if len(rdsMetrics) > 0 {
		response.RDS = rdsMetrics
	}

	albMetrics := fetchMetrics("LoadBalancer", "app/closetalk-production/d5eb857429f5a318", []string{"RequestCount", "TargetResponseTime"}, "AWS/ApplicationELB")
	if len(albMetrics) > 0 {
		response.ALB = albMetrics
	}

	writeJSON(w, http.StatusOK, response)
}

type CostPoint struct {
	Date    string  `json:"date"`
	Blended float64 `json:"blended"`
}

type CostService struct {
	Service string  `json:"service"`
	Blended float64 `json:"blended"`
}

type CostResponse struct {
	Daily     []CostPoint   `json:"daily"`
	ByService []CostService `json:"by_service"`
	Total     float64       `json:"total"`
}

func handleInfrastructureCosts(w http.ResponseWriter, r *http.Request) {
	ce := getCEClient()
	if ce == nil {
		writeJSON(w, http.StatusOK, CostResponse{})
		return
	}

	now := time.Now()
	currentYear, currentMonth, _ := now.Date()
	startOfMonth := time.Date(currentYear, currentMonth, 1, 0, 0, 0, 0, now.Location())
	tomorrow := now.AddDate(0, 0, 1)

	out, err := ce.GetCostAndUsage(context.Background(), &costexplorer.GetCostAndUsageInput{
		TimePeriod: &cetypes.DateInterval{
			Start: aws.String(startOfMonth.Format("2006-01-02")),
			End:   aws.String(tomorrow.Format("2006-01-02")),
		},
		Granularity: cetypes.GranularityDaily,
		Metrics:     []string{"BlendedCost"},
		GroupBy: []cetypes.GroupDefinition{{
			Type: "DIMENSION",
			Key:  aws.String("SERVICE"),
		}},
	})
	if err != nil {
		log.Printf("[infra] cost explorer: %v", err)
		writeJSON(w, http.StatusOK, CostResponse{})
		return
	}

	dailyMap := map[string]float64{}
	serviceMap := map[string]float64{}
	var total float64

	for _, result := range out.ResultsByTime {
		date := *result.TimePeriod.Start
		for _, group := range result.Groups {
			serviceName := "Other"
			if len(group.Keys) > 0 {
				serviceName = group.Keys[0]
			}
			amount := 0.0
			if group.Metrics != nil {
				if m, ok := group.Metrics["BlendedCost"]; ok && m.Amount != nil {
					amount, _ = strconv.ParseFloat(*m.Amount, 64)
				}
			}
			dailyMap[date] += amount
			serviceMap[serviceName] += amount
			total += amount
		}
	}

	total = math.Round(total*100) / 100
	daily := []CostPoint{}
	for date, amt := range dailyMap {
		daily = append(daily, CostPoint{Date: date, Blended: math.Round(amt*100) / 100})
	}
	sortPointsByDate(daily)

	byService := []CostService{}
	for svc, amt := range serviceMap {
		byService = append(byService, CostService{Service: svc, Blended: math.Round(amt*100) / 100})
	}
	sortServicesByCost(byService)

	writeJSON(w, http.StatusOK, CostResponse{
		Daily:     daily,
		ByService: byService,
		Total:     total,
	})
}

type InfraActionRequest struct {
	Email string `json:"email"`
	OTP   string `json:"otp,omitempty"`
}

type InfraActionResponse struct {
	Message string `json:"message"`
	Email   string `json:"email,omitempty"`
}

func handleInfrastructureStopInit(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	email := getUserEmail(userID)
	if email == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "NO_EMAIL", Message: "could not determine admin email"})
		return
	}

	cooldownKey := "otp_infra_cooldown:" + email
	if database.Valkey != nil {
		exists, _ := database.Valkey.Exists(context.Background(), cooldownKey).Result()
		if exists > 0 {
			ttl, _ := database.Valkey.TTL(context.Background(), cooldownKey).Result()
			writeError(w, http.StatusTooManyRequests, &model.AppError{
				Code:    "COOLDOWN",
				Message: fmt.Sprintf("please wait %d seconds before requesting another OTP", int(ttl.Seconds())),
			})
			return
		}
	}

	otp := generateOTP()
	otpKey := "otp_infra_stop:" + email
	if database.Valkey != nil {
		database.Valkey.Set(context.Background(), otpKey, otp, 10*time.Minute)
		database.Valkey.Set(context.Background(), cooldownKey, "1", 60*time.Second)
	}

	subject := "CloseTalk: Infrastructure STOP Confirmation"
	body := fmt.Sprintf(`You requested to STOP all CloseTalk infrastructure.

Your confirmation code is: %s

This code expires in 10 minutes. If you did not request this, please check your account security immediately.`, otp)
	sendEmail(context.Background(), email, subject, body)

	log.Printf("[infra] stop OTP sent to %s", email)
	writeJSON(w, http.StatusOK, InfraActionResponse{
		Message: "OTP sent to admin email",
		Email:   email,
	})
}

func handleInfrastructureStopConfirm(w http.ResponseWriter, r *http.Request) {
	var req InfraActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_REQUEST", Message: "invalid request body"})
		return
	}

	otpKey := "otp_infra_stop:" + req.Email
	if database.Valkey == nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "CACHE_ERR", Message: "cache unavailable"})
		return
	}

	stored, err := database.Valkey.Get(context.Background(), otpKey).Result()
	if err == redis.Nil || stored != req.OTP {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "INVALID_OTP", Message: "invalid or expired OTP"})
		return
	}

	database.Valkey.Del(context.Background(), otpKey)
	doStopInfrastructure(w, r)
}

func doStopInfrastructure(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	clusterName := os.Getenv("ECS_CLUSTER")
	if clusterName == "" {
		clusterName = "closetalk-production"
	}

	var errs []string

	ecsCli := getECSClient()
	if ecsCli != nil {
		for _, svc := range []string{"auth-service", "message-service"} {
			_, err := ecsCli.UpdateService(ctx, &ecs.UpdateServiceInput{
				Cluster:      aws.String(clusterName),
				Service:      aws.String(svc),
				DesiredCount: aws.Int32(0),
			})
			if err != nil {
				log.Printf("[infra] stop ecs %s: %v", svc, err)
				errs = append(errs, fmt.Sprintf("ecs %s: %v", svc, err))
			}
		}
	}

	rdsCli := getRDSClient()
	if rdsCli != nil {
		_, err := rdsCli.StopDBInstance(ctx, &rds.StopDBInstanceInput{
			DBInstanceIdentifier: aws.String("closetalk-production"),
		})
		if err != nil {
			log.Printf("[infra] stop rds: %v", err)
			errs = append(errs, fmt.Sprintf("rds: %v", err))
		}
	}

	if len(errs) > 0 {
		writeJSON(w, http.StatusOK, InfraActionResponse{
			Message: fmt.Sprintf("infrastructure stop initiated with %d warning(s): %s", len(errs), strings.Join(errs, "; ")),
		})
		return
	}

	log.Printf("[infra] infrastructure stop initiated by admin")
	writeJSON(w, http.StatusOK, InfraActionResponse{
		Message: "infrastructure stop initiated successfully. ECS and RDS are being stopped.",
	})
}

func handleInfrastructureStartInit(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	email := getUserEmail(userID)
	if email == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "NO_EMAIL", Message: "could not determine admin email"})
		return
	}

	cooldownKey := "otp_infra_cooldown:" + email
	if database.Valkey != nil {
		exists, _ := database.Valkey.Exists(context.Background(), cooldownKey).Result()
		if exists > 0 {
			ttl, _ := database.Valkey.TTL(context.Background(), cooldownKey).Result()
			writeError(w, http.StatusTooManyRequests, &model.AppError{
				Code:    "COOLDOWN",
				Message: fmt.Sprintf("please wait %d seconds before requesting another OTP", int(ttl.Seconds())),
			})
			return
		}
	}

	otp := generateOTP()
	otpKey := "otp_infra_start:" + email
	if database.Valkey != nil {
		database.Valkey.Set(context.Background(), otpKey, otp, 10*time.Minute)
		database.Valkey.Set(context.Background(), cooldownKey, "1", 60*time.Second)
	}

	subject := "CloseTalk: Infrastructure START Confirmation"
	body := fmt.Sprintf(`You requested to START all CloseTalk infrastructure.

Your confirmation code is: %s

This code expires in 10 minutes. If you did not request this, please check your account security immediately.`, otp)
	sendEmail(context.Background(), email, subject, body)

	log.Printf("[infra] start OTP sent to %s", email)
	writeJSON(w, http.StatusOK, InfraActionResponse{
		Message: "OTP sent to admin email",
		Email:   email,
	})
}

func handleInfrastructureStartConfirm(w http.ResponseWriter, r *http.Request) {
	var req InfraActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_REQUEST", Message: "invalid request body"})
		return
	}

	otpKey := "otp_infra_start:" + req.Email
	if database.Valkey == nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "CACHE_ERR", Message: "cache unavailable"})
		return
	}

	stored, err := database.Valkey.Get(context.Background(), otpKey).Result()
	if err == redis.Nil || stored != req.OTP {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "INVALID_OTP", Message: "invalid or expired OTP"})
		return
	}

	database.Valkey.Del(context.Background(), otpKey)
	doStartInfrastructure(w, r)
}

func doStartInfrastructure(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	clusterName := os.Getenv("ECS_CLUSTER")
	if clusterName == "" {
		clusterName = "closetalk-production"
	}

	var errs []string

	rdsCli := getRDSClient()
	if rdsCli != nil {
		_, err := rdsCli.StartDBInstance(ctx, &rds.StartDBInstanceInput{
			DBInstanceIdentifier: aws.String("closetalk-production"),
		})
		if err != nil {
			log.Printf("[infra] start rds: %v", err)
			errs = append(errs, fmt.Sprintf("rds: %v", err))
		}
	}

	ecsCli := getECSClient()
	if ecsCli != nil {
		for _, svc := range []string{"auth-service", "message-service"} {
			_, err := ecsCli.UpdateService(ctx, &ecs.UpdateServiceInput{
				Cluster:      aws.String(clusterName),
				Service:      aws.String(svc),
				DesiredCount: aws.Int32(1),
			})
			if err != nil {
				log.Printf("[infra] start ecs %s: %v", svc, err)
				errs = append(errs, fmt.Sprintf("ecs %s: %v", svc, err))
			}
		}
	}

	if len(errs) > 0 {
		writeJSON(w, http.StatusOK, InfraActionResponse{
			Message: fmt.Sprintf("infrastructure start initiated with %d warning(s): %s", len(errs), strings.Join(errs, "; ")),
		})
		return
	}

	log.Printf("[infra] infrastructure start initiated by admin")
	writeJSON(w, http.StatusOK, InfraActionResponse{
		Message: "infrastructure start initiated successfully. ECS and RDS are being started.",
	})
}

func getUserEmail(userID string) string {
	if userID == "" {
		return ""
	}
	var email string
	err := database.Pool.QueryRow(context.Background(), "SELECT email FROM users WHERE id = $1", userID).Scan(&email)
	if err != nil {
		log.Printf("[infra] get user email %s: %v", userID, err)
		return ""
	}
	return email
}

func sortPointsByDate(points []CostPoint) {
	for i := 0; i < len(points); i++ {
		for j := i + 1; j < len(points); j++ {
			if points[i].Date > points[j].Date {
				points[i], points[j] = points[j], points[i]
			}
		}
	}
}

func sortServicesByCost(services []CostService) {
	for i := 0; i < len(services); i++ {
		for j := i + 1; j < len(services); j++ {
			if services[i].Blended < services[j].Blended {
				services[i], services[j] = services[j], services[i]
			}
		}
	}
}
